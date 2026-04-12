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
    epochs = 20 # Kept at 20 to give the model time to learn the messy augmented data
    print(f"Training 784->128->10 MLP on MNIST for {epochs} epochs...")
    
    # NEW: Data Augmentation simulates imperfect human GUI drawings!
    train_transform = transforms.Compose([
        transforms.RandomAffine(degrees=15, translate=(0.1, 0.1), scale=(0.8, 1.2)),
        transforms.ToTensor(),
        transforms.Normalize((0.5,), (0.5,))
    ])
    
    # Standard transform for testing
    test_transform = transforms.Compose([
        transforms.ToTensor(),
        transforms.Normalize((0.5,), (0.5,))
    ])

    train_loader = torch.utils.data.DataLoader(datasets.MNIST('./data', train=True, download=True, transform=train_transform), batch_size=64, shuffle=True)
    test_loader = torch.utils.data.DataLoader(datasets.MNIST('./data', train=False, transform=test_transform), batch_size=1000, shuffle=False)
    
    model = MNIST_MLP()
    optimizer = optim.Adam(model.parameters(), lr=0.001)
    criterion = nn.CrossEntropyLoss()

    for epoch in range(epochs):
        model.train()
        running_loss = 0.0
        for batch_idx, (data, target) in enumerate(train_loader):
            optimizer.zero_grad()
            output = model(data)
            loss = criterion(output, target)
            loss.backward()
            optimizer.step()
            running_loss += loss.item()
            
        # Evaluate accuracy at the end of each epoch
        model.eval()
        correct = 0
        with torch.no_grad():
            for data, target in test_loader:
                output = model(data)
                pred = output.argmax(dim=1, keepdim=True)
                correct += pred.eq(target.view_as(pred)).sum().item()
        
        accuracy = 100. * correct / len(test_loader.dataset)
        print(f"Epoch {epoch+1}/{epochs} | Loss: {running_loss/len(train_loader):.4f} | Test Accuracy: {accuracy:.2f}%")
        
    return model

# --- 2. Quantization & Export ---
def export_mem_packed(filename, data_int8):
    with open(filename, 'w') as f:
        remainder = len(data_int8) % 4
        if remainder != 0: data_int8 = np.pad(data_int8, (0, 4 - remainder), 'constant')
        for i in range(0, len(data_int8), 4):
            b0 = int(data_int8[i])   & 0xFF
            b1 = int(data_int8[i+1]) & 0xFF
            b2 = int(data_int8[i+2]) & 0xFF
            b3 = int(data_int8[i+3]) & 0xFF
            word32 = (b3 << 24) | (b2 << 16) | (b1 << 8) | b0
            f.write(f"{word32:08x}\n")

def export_mem_int32(filename, data_int32):
    with open(filename, 'w') as f:
        for val in data_int32:
            f.write(f"{int(val) & 0xFFFFFFFF:08x}\n")

def main():
    model = train_model()
    model.eval()
    
    # Save the trained model for the GUI
    os.makedirs("../quantize", exist_ok=True)
    torch.save(model.state_dict(), "../quantize/mnist_model.pth")
    print("\nSaved PyTorch model to ../quantize/mnist_model.pth")
    
    W1 = model.fc1.weight.detach().numpy()
    b1 = model.fc1.bias.detach().numpy()
    W2 = model.fc2.weight.detach().numpy()
    
    # We detach b2 but won't use it directly in hardware due to equalization
    b2 = model.fc2.bias.detach().numpy() 

    # Scale weights
    scale_W1 = np.max(np.abs(W1)) / 127.0
    W1_int8 = np.clip(np.round(W1 / scale_W1), -128, 127).astype(np.int8)
    
    scale_W2 = np.max(np.abs(W2)) / 127.0
    W2_int8 = np.clip(np.round(W2 / scale_W2), -128, 127).astype(np.int8)

    # Calculate exact fixed-point multiplier for the C-Code
    L1_MULT = int(np.round(scale_W1 * 65536.0))

    scale_input = 1.0 / 127.0
    b1_int32 = np.round(b1 / (scale_W1 * scale_input)).astype(np.int32)
    
    # =========================================================================
    # NEUTRAL BIAS EQUALIZATION
    # Instead of using learned biases which favor certain digits (like '5'),
    # we force every class to start at exactly 5,000,000.
    # This ensures the FPGA's choice is based 100% on your drawing.
    # =========================================================================
    b2_int32 = np.full(10, 5000000, dtype=np.int32) 

    # Flatten row-by-row to perfectly match hardware MAC lanes
    W1_flat = W1_int8.reshape(-1)
    W2_flat = W2_int8.reshape(-1)

    W_all_flat = np.concatenate((W1_flat, W2_flat))
    b_all_int32 = np.concatenate((b1_int32, b2_int32))

    os.makedirs("../mem", exist_ok=True)
    os.makedirs("../../sw/c", exist_ok=True)

    print("Exporting merged .mem files for BRAM initialization...")
    export_mem_packed("../mem/weights_all.mem", W_all_flat)
    export_mem_int32("../mem/bias_all.mem", b_all_int32)

    print("Exporting weights.h for C workloads...")
    with open("../../sw/c/weights.h", 'w') as f:
        f.write("#pragma once\n\n")
        f.write(f"#define L1_MULT {L1_MULT}\n\n")  
        
    print("Done!")

if __name__ == "__main__":
    main()
