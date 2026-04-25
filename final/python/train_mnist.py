import numpy as np
import os
import shutil
import warnings
from sklearn.datasets import fetch_openml
from sklearn.neural_network import MLPClassifier
from sklearn.exceptions import ConvergenceWarning
warnings.filterwarnings("ignore", category=ConvergenceWarning)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, "..", "data")
ROOT_DIR = os.path.join(SCRIPT_DIR, "..")
os.makedirs(DATA_DIR, exist_ok=True)

HIDDEN = 128

def export_to_mem(data, filename):
    """Packs 4 INT8 bytes into one 32-bit hex word (little-endian).
    
    Byte layout: word = (b3<<24)|(b2<<16)|(b1<<8)|b0
    So byte 0 is at bits [7:0].
    """
    with open(filename, 'w') as f:
        padded = np.pad(data, (0, (4 - len(data) % 4) % 4), 'constant')
        reshaped = padded.reshape(-1, 4)
        for row in reshaped:
            b0, b1, b2, b3 = [int(x) & 0xFF for x in row]
            word = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
            f.write(f"{word:08x}\n")

def copy_to_root(filename):
    """Copy a .mem file from data/ to root for BRAM $readmemh."""
    src = os.path.join(DATA_DIR, filename)
    dst = os.path.join(ROOT_DIR, filename)
    shutil.copy2(src, dst)
    print(f"  Copied {filename} to project root")

def simulate_hw_inference(W1_q, b1_q, W2_q, b2_q, X_hw, inter_shift):
    """Simulate the exact hardware inference pipeline in Python."""
    # Layer 1: INT8 weights x UINT8 inputs + INT32 bias → ReLU → right-shift → clip to uint8
    l1_out = X_hw.astype(np.int32) @ W1_q.astype(np.int32).T + b1_q  # (N, 128)
    l1_relu = np.maximum(0, l1_out)  # ReLU
    l1_scaled = (l1_relu >> inter_shift).clip(0, 127).astype(np.uint8)  # Scale to uint8
    
    # Layer 2: INT8 weights x UINT8 intermediate + INT32 bias → argmax
    l2_out = l1_scaled.astype(np.int32) @ W2_q.astype(np.int32).T + b2_q  # (N, 10)
    preds = np.argmax(l2_out, axis=1)
    return preds

def train_and_export():
    print("=" * 55)
    print("  NeuroCore MNIST Training — 2-Layer MLP")
    print("=" * 55)
    
    print("\n[1/5] Fetching MNIST dataset...")
    X, y = fetch_openml('mnist_784', version=1, return_X_y=True, as_frame=False, parser='auto')
    y = y.astype(int)
    
    X_train, y_train = X[:60000] / 255.0, y[:60000]
    X_test, y_test   = X[60000:] / 255.0, y[60000:]
    
    print(f"  Training set: {X_train.shape[0]} samples")
    print(f"  Test set:     {X_test.shape[0]} samples")
    
    print(f"\n[2/5] Training 2-layer MLP (784->{HIDDEN}->10)...")
    model = MLPClassifier(
        hidden_layer_sizes=(HIDDEN,),
        activation='relu',
        solver='adam',
        max_iter=50,
        batch_size=256,
        learning_rate_init=0.001,
        random_state=42,
    )
    model.fit(X_train, y_train)
    
    float_acc = model.score(X_test, y_test)
    print(f"  Float accuracy: {float_acc*100:.2f}%")
    
    # Extract weights (sklearn uses column-major: coefs_[0] is (784, 128), we need (128, 784))
    W1_float = model.coefs_[0].T    # (128, 784)
    b1_float = model.intercepts_[0]  # (128,)
    W2_float = model.coefs_[1].T    # (10, 128)
    b2_float = model.intercepts_[1]  # (10,)
    
    print(f"  W1: {W1_float.shape}, W2: {W2_float.shape}")
    
    print("\n[3/5] Finding optimal quantization parameters...")
    
    # Hardware input scaling (same as draw_and_send.py preprocessing)
    X_hw = (X_test * 127.5).astype(np.uint8)
    
    best_acc = 0
    best_params = None
    
    for w1_scale in [32, 48, 64, 80, 96]:
        W1_q = (W1_float * w1_scale).clip(-128, 127).astype(np.int8)
        b1_scale = w1_scale * 127.5
        b1_q = (b1_float * b1_scale).astype(np.int32)
        
        # Find best inter_shift: L1 output magnitude determines this
        l1_out = X_hw[:1000].astype(np.int32) @ W1_q.astype(np.int32).T + b1_q
        l1_relu = np.maximum(0, l1_out)
        p95 = int(np.percentile(l1_relu[l1_relu > 0], 95))
        
        for inter_shift in range(6, 16):
            if p95 >> inter_shift < 5:
                continue  # too aggressive, loses info
            if p95 >> inter_shift > 200:
                continue  # not enough shift
            
            l1_scaled = (l1_relu >> inter_shift).clip(0, 127).astype(np.uint8)
            
            # Find best w2_scale for this inter_shift
            for w2_scale in [32, 48, 64, 80, 96]:
                W2_q = (W2_float * w2_scale).clip(-128, 127).astype(np.int8)
                # b2 must be in same units as W2_q @ l1_scaled
                # l1_scaled ≈ l1_real * b1_scale / 2^inter_shift
                # W2_q ≈ W2_float * w2_scale
                # So product ≈ w2_scale * b1_scale / 2^inter_shift * (W2_float @ l1_real)
                # Bias must match: b2_q = b2_float * w2_scale * b1_scale / 2^inter_shift
                b2_q_scale = w2_scale * b1_scale / (1 << inter_shift)
                b2_q = (b2_float * b2_q_scale).astype(np.int32)
                
                # Full test
                preds = simulate_hw_inference(W1_q, b1_q, W2_q, b2_q, X_hw[:1000], inter_shift)
                acc = np.mean(preds == y_test[:1000].astype(int))
                
                if acc > best_acc:
                    best_acc = acc
                    best_params = (w1_scale, w2_scale, inter_shift, W1_q, b1_q, W2_q, b2_q, b2_q_scale)
    
    w1_scale, w2_scale, inter_shift, W1_q, b1_q, W2_q, b2_q, b2_q_scale = best_params
    print(f"  Best: w1_scale={w1_scale}, w2_scale={w2_scale}, inter_shift={inter_shift}")
    
    # Full test set evaluation
    preds = simulate_hw_inference(W1_q, b1_q, W2_q, b2_q, X_hw, inter_shift)
    full_acc = np.mean(preds == y_test.astype(int))
    print(f"  Full test quantized accuracy: {full_acc*100:.2f}%")
    
    print(f"\n[4/5] Exporting to {DATA_DIR}...")
    print(f"  W1 range: [{W1_q.min()}, {W1_q.max()}]")
    print(f"  W2 range: [{W2_q.min()}, {W2_q.max()}]")
    print(f"  b1 range: [{b1_q.min()}, {b1_q.max()}]")
    print(f"  b2 range: [{b2_q.min()}, {b2_q.max()}]")
    print(f"  inter_shift: {inter_shift}")
    
    # Weights: Layer1 then Layer2, contiguous in one file
    w1_flat = W1_q.flatten()  # 128*784 = 100352 bytes
    w2_flat = W2_q.flatten()  # 10*128 = 1280 bytes
    all_weights = np.concatenate([w1_flat, w2_flat])
    export_to_mem(all_weights, os.path.join(DATA_DIR, "weights.mem"))
    
    # Biases: Layer1 (128 entries) then Layer2 (10 entries), padded to 256
    with open(os.path.join(DATA_DIR, "bias.mem"), 'w') as f:
        padded_biases = np.zeros(256, dtype=np.int32)
        padded_biases[:HIDDEN] = b1_q
        padded_biases[HIDDEN:HIDDEN+10] = b2_q
        for b in padded_biases:
            f.write(f"{int(b) & 0xFFFFFFFF:08x}\n")
    
    # Save config for verification
    config_path = os.path.join(DATA_DIR, "config.txt")
    w1_words = (len(w1_flat) + 3) // 4
    w2_base = w1_words
    with open(config_path, 'w') as f:
        f.write(f"hidden={HIDDEN}\n")
        f.write(f"l1_rows={HIDDEN}\n")
        f.write(f"l1_cols=784\n")
        f.write(f"l2_rows=10\n")
        f.write(f"l2_cols={HIDDEN}\n")
        f.write(f"l2_wt_base={w2_base}\n")
        f.write(f"l2_bias_base={HIDDEN}\n")
        f.write(f"inter_shift={inter_shift}\n")
        f.write(f"w1_scale={w1_scale}\n")
        f.write(f"w2_scale={w2_scale}\n")
    
    print(f"  L2 weight base addr: {w2_base}")
    
    print(f"\n[5/5] Copying to project root...")
    copy_to_root("weights.mem")
    copy_to_root("bias.mem")
    
    print(f"\n{'=' * 55}")
    print(f"  DONE! 2-Layer MLP Quantized accuracy: {full_acc*100:.2f}%")
    print(f"  inter_shift={inter_shift}, L2 wt_base={w2_base}")
    print(f"  Re-run Vivado synthesis to embed weights in bitstream.")
    print(f"{'=' * 55}")

if __name__ == "__main__":
    train_and_export()
