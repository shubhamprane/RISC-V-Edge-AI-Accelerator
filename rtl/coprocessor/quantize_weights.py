import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms
import numpy as np
import os

# --- 1. Define and Train the Model ---
class MNIST_MLP(nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1 = nn.Linear(784, 128)
        self.fc2 = nn.Linear(128, 10)

    def forward(self, x):
        x = x.view(-1, 784)
        x = torch.relu(self.fc1(x))
        x = self.fc2(x)
        return x

def train_model():
    print("Training 784->128->10 MLP on MNIST for 1 epoch...")
    transform = transforms.Compose([transforms.ToTensor(), transforms.Normalize((0.1307,), (0.3081,))])
    train_loader = torch.utils.data.DataLoader(datasets.MNIST('./data', train=True, download=True, transform=transform), batch_size=64, shuffle=True)
    
    model = MNIST_MLP()
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    criterion = nn.CrossEntropyLoss()

    model.train()
    for batch_idx, (data, target) in enumerate(train_loader):
        optimizer.zero_grad()
        output = model(data)
        loss = criterion(output, target)
        loss.backward()
        optimizer.step()
        if batch_idx % 200 == 0:
            print(f"Batch {batch_idx}/{len(train_loader)} - Loss: {loss.item():.4f}")
    
    return model

# --- 2. Quantization & Export ---
def export_mem_packed(filename, data_int8):
    """Packs four INT8 values into one 32-bit hex string per line."""
    with open(filename, 'w') as f:
        # Pad data with zeros if not a multiple of 4
        remainder = len(data_int8) % 4
        if remainder != 0:
            data_int8 = np.pad(data_int8, (0, 4 - remainder), 'constant')
            
        for i in range(0, len(data_int8), 4):
            # Read 4 bytes (Little Endian packing to match Verilog)
            b0 = data_int8[i]   & 0xFF
            b1 = data_int8[i+1] & 0xFF
            b2 = data_int8[i+2] & 0xFF
            b3 = data_int8[i+3] & 0xFF
            word32 = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
            f.write(f"{word32:08x}\n")

def export_mem_int32(filename, data_int32):
    """Exports INT32 values, one per line."""
    with open(filename, 'w') as f:
        for val in data_int32:
            f.write(f"{val & 0xFFFFFFFF:08x}\n")

def main():
    model = train_model()
    
    # Extract weights and biases
    W1 = model.fc1.weight.detach().numpy() # Shape: (128, 784)
    b1 = model.fc1.bias.detach().numpy()   # Shape: (128,)
    W2 = model.fc2.weight.detach().numpy() # Shape: (10, 128)
    b2 = model.fc2.bias.detach().numpy()   # Shape: (10,)

    # Quantize W1 and W2 to INT8
    scale_W1 = np.max(np.abs(W1)) / 127.0
    W1_int8 = np.clip(np.round(W1 / scale_W1), -128, 127).astype(np.int8)
    
    scale_W2 = np.max(np.abs(W2)) / 127.0
    W2_int8 = np.clip(np.round(W2 / scale_W2), -128, 127).astype(np.int8)

    # Scale biases to INT32 (using an arbitrary scaling factor matching the weights)
    # In a rigorous quantization, this involves the input scale as well.
    b1_int32 = np.round(b1 / scale_W1).astype(np.int32)
    b2_int32 = np.round(b2 / scale_W2).astype(np.int32)

    os.makedirs("../mem", exist_ok=True)
    os.makedirs("../../sw/c", exist_ok=True)

    # Flatten arrays
    W1_flat = W1_int8.flatten()
    W2_flat = W2_int8.flatten()

    print("Exporting .mem files for BRAM initialization...")
    export_mem_packed("../mem/weights_layer1.mem", W1_flat)
    export_mem_int32("../mem/bias_layer1.mem", b1_int32)
    export_mem_packed("../mem/weights_layer2.mem", W2_flat)
    export_mem_int32("../mem/bias_layer2.mem", b2_int32)

    print("Exporting weights.h for C workloads...")
    with open("../../sw/c/weights.h", 'w') as f:
        f.write("#pragma once\n\n")
        f.write(f"const signed char W1[{len(W1_flat)}] = {{ {','.join(map(str, W1_flat))} }};\n")
        f.write(f"const int b1[{len(b1_int32)}] = {{ {','.join(map(str, b1_int32))} }};\n")
        f.write(f"const signed char W2[{len(W2_flat)}] = {{ {','.join(map(str, W2_flat))} }};\n")
        f.write(f"const int b2[{len(b2_int32)}] = {{ {','.join(map(str, b2_int32))} }};\n")

    print("Done!")

if __name__ == "__main__":
    main()