import serial
import struct
import time

def monitor_speedup(port='COM3', baud=115200):
    print(f"Connecting to FPGA on {port}...")
    try:
        ser = serial.Serial(port, baud, timeout=1)
    except Exception as e:
        print(f"Error: Could not open serial port {port}. {e}")
        return

    print("Waiting for FPGA benchmark packet (48 bytes)...")
    print("ACTION REQUIRED: Go to your GUI and draw a digit to trigger the inference.")
    
    while True:
        if ser.in_waiting >= 48:
            raw_data = ser.read(48)
            # Unpack 12 little-endian uint32 (4 bytes each)
            words = struct.unpack('<12I', raw_data)
            
            scores = words[0:10]
            hw_cycles = words[10]
            sw_cycles = words[11]
            
            print("\n" + "="*50)
            print("         FPGA SPEEDUP BENCHMARK RESULTS")
            print("="*50)
            print(f"Hardware Calculation: {hw_cycles:,} cycles")
            print(f"Software Calculation: {sw_cycles:,} cycles")
            
            if hw_cycles > 0:
                speedup = sw_cycles / hw_cycles
                print(f"ARCHITECTURAL SPEEDUP: {speedup:.2f} x")
            
            print("-" * 30)
            print("ArgMax Scores (Raw):")
            for i, s in enumerate(scores):
                # Convert back to signed if needed (struct.unpack 'I' is unsigned)
                val = struct.unpack('<i', struct.pack('<I', s))[0]
                print(f"  Class {i}: {val:10d}")
            print("="*50 + "\n")
            
            # Flush buffer for next run
            ser.reset_input_buffer()
        time.sleep(0.1)

if __name__ == "__main__":
    # Change 'COM3' to your actual FPGA port (e.g., /dev/ttyUSB1 on Linux)
    monitor_speedup(port='COM8')
