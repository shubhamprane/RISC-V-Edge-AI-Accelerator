import numpy as np
import time

def benchmark_pc():
    # Model parameters
    input_size = 784
    hidden_size = 128
    output_size = 10
    inter_shift = 11

    # Initialize random weights/biases for benchmarking
    W1 = np.random.randint(-128, 127, (hidden_size, input_size), dtype=np.int8)
    b1 = np.random.randint(-1000, 1000, hidden_size, dtype=np.int32)
    W2 = np.random.randint(-128, 127, (output_size, hidden_size), dtype=np.int8)
    b2 = np.random.randint(-1000, 1000, output_size, dtype=np.int32)
    
    input_vec = np.random.randint(-128, 127, input_size, dtype=np.int8)

    # Benchmark loop
    iterations = 1000
    start_time = time.time()
    
    for _ in range(iterations):
        # Layer 1
        l1_out = np.dot(W1.astype(np.int32), input_vec.astype(np.int32)) + b1
        l1_relu = np.maximum(0, l1_out)
        l1_scaled = (l1_relu >> inter_shift).clip(0, 127).astype(np.uint8)
        
        # Layer 2
        scores = np.dot(W2.astype(np.int32), l1_scaled.astype(np.int32)) + b2
        
        # Argmax
        predicted_class = np.argmax(scores)

    end_time = time.time()
    total_time = end_time - start_time
    avg_latency = total_time / iterations
    
    # Calculate MACs
    # Layer 1: 128 * 784 MACs
    # Layer 2: 10 * 128 MACs
    total_macs = (hidden_size * input_size) + (output_size * hidden_size)
    throughput_macs = total_macs / avg_latency
    
    print(f"PC Benchmark Results:")
    print(f"Average Latency: {avg_latency * 1000:.4f} ms")
    print(f"Total MACs per inference: {total_macs}")
    print(f"Throughput: {throughput_macs / 1e6:.4f} MMACs/s")
    
    return avg_latency, total_macs

if __name__ == "__main__":
    benchmark_pc()
