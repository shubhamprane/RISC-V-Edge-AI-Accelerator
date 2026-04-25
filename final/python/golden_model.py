import numpy as np

def int8_mac_golden(a, b, bias, relu_en=True):
    """
    Python golden model for the Vector MAC Hardware.
    a, b: arrays of INT8
    bias: INT32
    """
    # 1. INT8 Multiplication and INT32 Accumulation
    dot_product = np.dot(a.astype(np.int32), b.astype(np.int32))
    
    # 2. Add Bias
    result = dot_product + bias
    
    # 3. ReLU
    if relu_en:
        result = max(0, result)
        
    return result

if __name__ == "__main__":
    # Test vector
    a = np.array([1, 2, -1, 4], dtype=np.int8)
    b = np.array([2, 2, 2, 2], dtype=np.int8)
    bias = 10
    
    hw_result = int8_mac_golden(a, b, bias)
    # 1*2 + 2*2 + -1*2 + 4*2 + 10 = 2 + 4 - 2 + 8 + 10 = 22
    print(f"Golden Model Result: {hw_result}")
