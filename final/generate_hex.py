import os

# Create an imem.hex filled with RISC-V NOPs (0x00000013)
with open('imem.hex', 'w') as f:
    for _ in range(1024):
        f.write("00000013\n")

# Create a dmem.hex filled with 0s
with open('dmem.hex', 'w') as f:
    for _ in range(1024):
        f.write("00000000\n")

print("Created imem.hex and dmem.hex")
