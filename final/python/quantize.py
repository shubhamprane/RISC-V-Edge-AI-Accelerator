import numpy as np
import os
import shutil

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, "..", "data")
ROOT_DIR = os.path.join(SCRIPT_DIR, "..")
os.makedirs(DATA_DIR, exist_ok=True)

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

if __name__ == "__main__":
    weights = np.zeros((10, 784), dtype=np.int8)
    
    # Set class 5 as the high-weight winner for testing
    weights[5, :] = 50
    
    weights_path = os.path.join(DATA_DIR, "weights.mem")
    export_to_mem(weights.flatten(), weights_path)
    
    # Input Vector - All ones
    inputs = np.ones(784, dtype=np.int8)
    input_path = os.path.join(DATA_DIR, "input.mem")
    export_to_mem(inputs, input_path)
    
    # Biases - All zeros
    biases = np.zeros(256, dtype=np.int32)
    bias_path = os.path.join(DATA_DIR, "bias.mem")
    with open(bias_path, 'w') as f:
        for b in biases:
            f.write(f"{b:08x}\n")
    
    # Copy to root directory for Vivado BRAM loading
    copy_to_root("weights.mem")
    copy_to_root("input.mem")
    copy_to_root("bias.mem")
    
    print("\nTest weights generated: Class 5 is the expected winner.")
