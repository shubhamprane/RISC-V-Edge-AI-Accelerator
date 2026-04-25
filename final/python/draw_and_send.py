# Requirements: pip install Pillow numpy pyserial
import tkinter as tk
from PIL import Image, ImageDraw
import numpy as np
import serial
import sys
import argparse
import struct
import time
from preprocess import preprocess_digit

# Sync header sent by FPGA before each 48-byte data payload
SYNC_HEADER = bytes([0xA5, 0x5A, 0xF0, 0x0F])

def get_args():
    parser = argparse.ArgumentParser(description='NeuroCore Digit Drawing Host App')
    parser.add_argument('port', nargs='?', default='COM5', help='Serial port (e.g. COM3 or /dev/ttyUSB0)')
    parser.add_argument('--baud', type=int, default=115200, help='Baud rate (default: 115200)')
    parser.add_argument('--clock', type=float, default=10.0, help='FPGA Clock Frequency in MHz (default: 10.0)')
    return parser.parse_args()

class DigitDrawingApp:
    def __init__(self, root, port, baud, clock_mhz):
        self.root = root
        self.port = port
        self.baud = baud
        self.clock_mhz = clock_mhz
        self.ser = None
        self.root.title("NeuroCore - Speedup Benchmark")
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)
        
        self.canvas_size = 280
        
        self.canvas = tk.Canvas(root, width=self.canvas_size, height=self.canvas_size, bg='black')
        self.canvas.pack()
        
        # PIL image for backend processing
        self.image = Image.new("L", (self.canvas_size, self.canvas_size), 0)
        self.draw = ImageDraw.Draw(self.image)
        
        self.canvas.bind("<B1-Motion>", self.paint)
        
        self.btn_send = tk.Button(root, text="Send to FPGA", command=self.send_to_fpga)
        self.btn_send.pack(side=tk.LEFT)
        
        self.btn_clear = tk.Button(root, text="Clear", command=self.clear_canvas)
        self.btn_clear.pack(side=tk.RIGHT)
        
        self.status = tk.Label(root, text=f"Serial: {self.port} @ {self.baud}")
        self.status.pack(side=tk.BOTTOM)
        
        # Open serial port once and keep it open
        try:
            self.ser = serial.Serial(self.port, self.baud, timeout=5)
            self.ser.reset_input_buffer()
            self.ser.reset_output_buffer()
            print(f"Serial port {self.port} opened at {self.baud} baud.")
        except serial.SerialException as e:
            print(f"Failed to open serial port: {e}")
            self.status.config(text="Error: Cannot open serial port", fg="red")
    
    def on_close(self):
        """Clean up serial port on window close."""
        if self.ser and self.ser.is_open:
            self.ser.close()
            print("Serial port closed.")
        self.root.destroy()

    def paint(self, event):
        r = 12
        x1, y1 = (event.x - r), (event.y - r)
        x2, y2 = (event.x + r), (event.y + r)
        self.canvas.create_oval(x1, y1, x2, y2, fill="white", outline="white")
        self.draw.ellipse([x1, y1, x2, y2], fill=255)

    def clear_canvas(self):
        self.canvas.delete("all")
        self.image = Image.new("L", (self.canvas_size, self.canvas_size), 0)
        self.draw = ImageDraw.Draw(self.image)
        self.status.config(text=f"Serial: {self.port} @ {self.baud}", fg="black")

    def find_sync_header(self):
        """Read bytes until the 4-byte sync header is found. Returns True on success."""
        buf = bytearray()
        deadline = time.time() + 5  # 5 second timeout
        
        while time.time() < deadline:
            byte = self.ser.read(1)
            if len(byte) == 0:
                continue
            buf.append(byte[0])
            # Keep only the last 4 bytes for matching
            if len(buf) > 4:
                buf.pop(0)
            if bytes(buf) == SYNC_HEADER:
                return True
        return False

    def send_to_fpga(self):
        if not self.ser or not self.ser.is_open:
            self.status.config(text="Error: Serial port not open", fg="red")
            return
            
        # MNIST-style preprocessing: center, normalize, scale
        flat_data = preprocess_digit(self.image, self.canvas_size, 28)
        
        print(f"Sending 784 bytes to {self.port}...")
        print(f"  Non-zero pixels: {np.count_nonzero(flat_data)}")
        print(f"  Max pixel value: {flat_data.max()}")
        try:
            # Drain any stale bytes from previous transactions
            self.ser.reset_input_buffer()
            
            # Send image data
            self.ser.write(flat_data.tobytes())
            print("Data sent! Waiting for FPGA response...")
            self.status.config(text="Status: Data Sent. Waiting for response...", fg="orange")
            self.root.update()
            
            # Wait for sync header (0xA5, 0x5A, 0xF0, 0x0F)
            if not self.find_sync_header():
                print("Error: Timed out waiting for sync header from FPGA.")
                self.status.config(text="Error: No sync header received", fg="red")
                return
            
            # Read 48 data bytes (12 x 32-bit integers: 10 scores + HW cycles + SW cycles)
            response = self.ser.read(48)
            
            if len(response) == 48:
                # Unpack 12 unsigned ints first to avoid signed overflow issues during initial fetch
                words = struct.unpack('<12I', response)
                # Convert first 10 to signed ints for scores
                scores = [struct.unpack('<i', struct.pack('<I', w))[0] for w in words[0:10]]
                hw_cycles = words[10]
                sw_cycles = words[11]
                
                # Latency Calculation (Strictly Calculation Time, excluding UART)
                # Clock is in MHz, so duration = cycles / (freq * 1e6)
                latency_ms = (hw_cycles / (self.clock_mhz * 1e6)) * 1000
                
                # Throughput Calculation
                # Total MACs = (128*784) + (10*128) = 101,632
                total_macs = 101632 
                throughput_mmacs = (total_macs / latency_ms) / 1000 if latency_ms > 0 else 0
                
                predicted_class = np.argmax(scores)
                
                print("\n" + "="*50)
                print("         FPGA SPEEDUP BENCHMARK RESULTS")
                print("      (Excludes UART Memory Transfer Time)")
                print("="*50)
                print(f"Hardware Calc Time: {latency_ms:.4f} ms ({hw_cycles:,} cycles @ {self.clock_mhz}MHz)")
                print(f"Software Calc Time: {(sw_cycles/(self.clock_mhz*1e6))*1000:.2f} ms ({sw_cycles:,} cycles)")
                print(f"FPGA Throughput:    {throughput_mmacs:.2f} MMACs/s")
                
                if hw_cycles > 0:
                    speedup = sw_cycles / hw_cycles
                    print(f"ARCHITECTURAL SPEEDUP: {speedup:.2f} x")
                
                print("-" * 30)
                print("--- FPGA Inference Results ---")
                for i, score in enumerate(scores):
                    marker = " <--- WINNER" if i == predicted_class else ""
                    print(f"Class {i}: {score:10d}{marker}")
                print(f"Final Prediction: {predicted_class}\n")
                print("="*50 + "\n")
                
                self.status.config(text=f"Success! FPGA Prediction: {predicted_class}", fg="green")
            else:
                print(f"Warning: Expected 48 bytes, got {len(response)} bytes.")
                self.status.config(text=f"Warning: Incomplete response ({len(response)}/48)", fg="red")
                    
        except serial.SerialException as e:
            msg = f"Serial Error: {e}\nCheck if FPGA is connected and port is correct."
            print(msg)
            self.status.config(text="Error: Serial Connection Failed", fg="red")
        except Exception as e:
            print(f"Error: {e}")
            self.status.config(text=f"Error: {e}", fg="red")

if __name__ == "__main__":
    args = get_args()
    root = tk.Tk()
    app = DigitDrawingApp(root, args.port, args.baud, args.clock)
    root.mainloop()
