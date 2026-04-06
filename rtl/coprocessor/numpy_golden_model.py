import numpy as np

def int8_mac_relu(vec_a, vec_b, bias):
    """
    Matches vec_mac_engine.v FSM behavior exactly.
    vec_a, vec_b: INT8 arrays of length N
    bias: INT32 scalar
    """
    # 1. Dot Product (Accumulation)
    acc = np.dot(vec_a.astype(np.int32), vec_b.astype(np.int32))
    
    # 2. Add Bias
    acc += bias
    
    # 3. Fused ReLU
    result = max(0, acc)
    return result

def systolic_layer(inp_vector, weights_matrix, bias_vector):
    """
    Matches the layer sequence of the coprocessor_top.v Master FSM.
    inp_vector: (N,)
    weights_matrix: (M, N) 
    bias_vector: (M,)
    """
    M = weights_matrix.shape[0]
    output = np.zeros(M, dtype=np.int32)
    
    # Process row by row just like the hardware FSM
    for i in range(M):
        output[i] = int8_mac_relu(inp_vector, weights_matrix[i], bias_vector[i])
        
    return output

def argmax10(logits):
    """Matches the combinational argmax_tree.v tournament."""
    return np.argmax(logits)

def full_inference(image_784_int8, W1_int8, b1_int32, W2_int8, b2_int32):
    """
    End-to-End hardware pipeline simulation.
    """
    # LAYER 1: 784 -> 128
    layer1_out = systolic_layer(image_784_int8, W1_int8, b1_int32)
    
    # LAYER 2: 128 -> 10 
    # Note: If Layer 2 has NO ReLU in hardware, you must adjust systolic_layer or int8_mac_relu.
    # Usually, final layer logic avoids ReLU so negative logits are preserved for argmax.
    layer2_out = np.zeros(10, dtype=np.int32)
    for i in range(10):
        # Using raw dot product + bias for the final layer (No ReLU)
        dot_prod = np.dot(layer1_out, W2_int8[i].astype(np.int32))
        layer2_out[i] = dot_prod + b2_int32[i]
        
    # ARGMAX
    prediction = argmax10(layer2_out)
    
    return prediction, layer2_out

if __name__ == "__main__":
    # Quick sanity check
    img = np.random.randint(-128, 127, 784, dtype=np.int8)
    w1 = np.random.randint(-10, 10, (128, 784), dtype=np.int8)
    b1 = np.random.randint(-100, 100, 128, dtype=np.int32)
    w2 = np.random.randint(-10, 10, (10, 128), dtype=np.int8)
    b2 = np.random.randint(-100, 100, 10, dtype=np.int32)
    
    pred, scores = full_inference(img, w1, b1, w2, b2)
    print(f"Sanity Check -> Prediction: {pred}, Logits: {scores}")