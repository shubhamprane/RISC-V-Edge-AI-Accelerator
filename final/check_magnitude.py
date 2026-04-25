import numpy as np
import os

def load_mem_packed(filename, total_bytes):
    """Loads a .mem file where 4 bytes are packed into a 32-bit little-endian hex word."""
    data = []
    if not os.path.exists(filename):
        print(f"Error: {filename} not found.")
        return np.zeros(total_bytes, dtype=np.int8)
    
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('/'): continue
            try:
                word = int(line, 16)
                for i in range(4):
                    val = (word >> (i*8)) & 0xFF
                    if val > 127: val -= 256
                    data.append(np.int8(val))
            except ValueError:
                continue
    return np.array(data[:total_bytes], dtype=np.int8)

def load_bias(filename, count):
    """Loads signed 32-bit hex values."""
    biases = []
    if not os.path.exists(filename):
        print(f"Error: {filename} not found.")
        return np.zeros(count, dtype=np.int32)
        
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('/'): continue
            try:
                val = int(line, 16)
                if val > 0x7FFFFFFF: val -= 0x100000000
                biases.append(val)
                if len(biases) == count: break
            except ValueError:
                continue
    return np.array(biases, dtype=np.int32)

def run_inference():
    ROOT_DIR = "/home/varun/hard_lab/goal_system"
    WEIGHTS_PATH = os.path.join(ROOT_DIR, "weights.mem")
    BIAS_PATH = os.path.join(ROOT_DIR, "bias.mem")
    
    HIDDEN = 128
    inter_shift = 11
    
    # Load weights and biases
    weights_flat = load_mem_packed(WEIGHTS_PATH, HIDDEN * 784 + 10 * HIDDEN)
    W1 = weights_flat[:HIDDEN * 784].reshape(HIDDEN, 784)
    W2 = weights_flat[HIDDEN * 784:].reshape(10, HIDDEN)
    
    all_biases = load_bias(BIAS_PATH, HIDDEN + 10)
    b1 = all_biases[:HIDDEN]
    b2 = all_biases[HIDDEN:]
    
    # Input of all 127s
    input_data = np.full(784, 127, dtype=np.int8)
    
    # Layer 1
    l1_out = np.dot(W1.astype(np.int32), input_data.astype(np.int32)) + b1
    l1_relu = np.maximum(0, l1_out)
    l1_scaled = (l1_relu >> inter_shift).clip(0, 127).astype(np.uint8)
    
    # Layer 2
    scores = np.dot(W2.astype(np.int32), l1_scaled.astype(np.int32)) + b2
    
    print("Final 10 scores:")
    for i, score in enumerate(scores):
        print(f"{i}: {score}")

if __name__ == "__main__":
    run_inference()
