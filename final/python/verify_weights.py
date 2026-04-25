import numpy as np
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, "..", "data")

def load_mem_packed(filename, total_bytes):
    """Loads a .mem file where 4 bytes are packed into a 32-bit little-endian hex word.
    
    export_to_mem packs as: word = (b3<<24)|(b2<<16)|(b1<<8)|b0
    So byte 0 is at bits [7:0] (little-endian).
    """
    data = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('/'): continue
            word = int(line, 16)
            # Unpack little-endian: byte 0 at bits [7:0], byte 1 at [15:8], etc.
            for i in range(4):
                val = (word >> (i*8)) & 0xFF
                if val > 127: val -= 256
                data.append(np.int8(val))
    return np.array(data[:total_bytes], dtype=np.int8)

def load_bias(filename, count):
    """Loads signed 32-bit hex values."""
    biases = []
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('/'): continue
            val = int(line, 16)
            if val > 0x7FFFFFFF: val -= 0x100000000
            biases.append(val)
            if len(biases) == count: break
    return np.array(biases, dtype=np.int32)

def verify():
    print("--- NeuroCore Weight Verification ---")
    
    weights_path = os.path.join(DATA_DIR, "weights.mem")
    bias_path = os.path.join(DATA_DIR, "bias.mem")
    input_path = os.path.join(DATA_DIR, "input.mem")
    
    HIDDEN = 128
    
    # Read config to get inter_shift
    inter_shift = 11
    config_path = os.path.join(DATA_DIR, "config.txt")
    if os.path.exists(config_path):
        with open(config_path, 'r') as f:
            for line in f:
                if line.startswith('inter_shift='):
                    inter_shift = int(line.strip().split('=')[1])
    
    # 1. Load Weights
    weights_flat = load_mem_packed(weights_path, HIDDEN * 784 + 10 * HIDDEN)
    W1 = weights_flat[:HIDDEN * 784].reshape(HIDDEN, 784)
    W2 = weights_flat[HIDDEN * 784:].reshape(10, HIDDEN)
    print(f"Loaded W1: {W1.shape}, W2: {W2.shape}")
    
    # 2. Load Biases
    all_biases = load_bias(bias_path, HIDDEN + 10)
    b1 = all_biases[:HIDDEN]
    b2 = all_biases[HIDDEN:]
    print(f"Loaded b1: {b1.shape}, b2: {b2.shape}")
    
    # 3. Load Input
    inputs = load_mem_packed(input_path, 784)
    print(f"Loaded input: {inputs.shape}, unique values: {np.unique(inputs)}")
    
    # 4. Perform Calculation matching hardware
    l1_out = np.dot(W1.astype(np.int32), inputs.astype(np.int32)) + b1
    l1_relu = np.maximum(0, l1_out)
    l1_scaled = (l1_relu >> inter_shift).clip(0, 127).astype(np.uint8)
    
    scores = np.dot(W2.astype(np.int32), l1_scaled.astype(np.int32)) + b2
    
    # 5. Argmax
    predicted_class = np.argmax(scores)
    
    print("\nResults:")
    for i in range(10):
        marker = " <--- WINNER" if i == predicted_class else ""
        print(f"Class {i}: {scores[i]}{marker}")
        
    print(f"\nFinal Prediction: {predicted_class}")

if __name__ == "__main__":
    verify()
