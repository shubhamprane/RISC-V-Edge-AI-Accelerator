# Requirements: pip install Pillow numpy pyserial
import tkinter as tk
from PIL import Image, ImageDraw
import numpy as np
import serial
import sys
import argparse
import struct
from preprocess import preprocess_digit

def get_args():
    parser = argparse.ArgumentParser(description='NeuroCore Digit Drawing Host App')
    parser.add_argument('port', nargs='?', default='COM8', help='Serial port (e.g. COM3 or /dev/ttyUSB0)')
    parser.add_argument('--baud', type=int, default=115200, help='Baud rate (default: 115200)')
    return parser.parse_args()

class DigitDrawingApp:
    def __init__(self, root, port, baud):
        self.root = root
        self.port = port
        self.baud = baud
        self.root.title("NeuroCore - Draw a Digit")
        
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

    def send_to_fpga(self):
        # MNIST-style preprocessing: center, normalize, scale
        flat_data = preprocess_digit(self.image, self.canvas_size, 28)
        
        print(f"Sending 784 bytes to {self.port}...")
        print(f"  Non-zero pixels: {np.count_nonzero(flat_data)}")
        print(f"  Max pixel value: {flat_data.max()}")
        try:
            with serial.Serial(self.port, self.baud, timeout=2) as ser:
                ser.write(flat_data.tobytes())
                print("Data sent! Waiting for FPGA response...")
                self.status.config(text="Status: Data Sent. Waiting for response...", fg="orange")
                self.root.update()
                
                # Read 40 bytes back (10 x 32-bit integers)
                response = ser.read(40)
                
                if len(response) == 40:
                    scores = struct.unpack('<10i', response)
                    predicted_class = np.argmax(scores)
                    
                    print("\n--- FPGA Inference Results ---")
                    for i, score in enumerate(scores):
                        marker = " <--- WINNER" if i == predicted_class else ""
                        print(f"Class {i}: {score:10d}{marker}")
                    print(f"Final Prediction: {predicted_class}\n")
                    
                    self.status.config(text=f"Success! FPGA Prediction: {predicted_class}", fg="green")
                else:
                    print(f"Warning: Expected 40 bytes, got {len(response)} bytes.")
                    self.status.config(text=f"Warning: Incomplete response ({len(response)}/40)", fg="red")
                    
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
    app = DigitDrawingApp(root, args.port, args.baud)
    root.mainloop()
