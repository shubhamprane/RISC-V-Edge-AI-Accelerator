import tkinter as tk
from tkinter import messagebox
import serial
import serial.tools.list_ports
import numpy as np
from PIL import Image, ImageDraw

BAUD_RATE = 115200
CANVAS_SIZE = 280   
BRUSH_SIZE = 20     

class NeuroCoreHostGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("RISC-V NeuroCore: Live Inference")
        self.root.geometry("400x550")
        self.serial_port = None
        self.setup_ui()
        self.image = Image.new("L", (CANVAS_SIZE, CANVAS_SIZE), color=0)
        self.draw  = ImageDraw.Draw(self.image)
        self.last_x, self.last_y = None, None

    def setup_ui(self):
        port_frame = tk.Frame(self.root)
        port_frame.pack(pady=10)
        tk.Label(port_frame, text="COM Port:").pack(side=tk.LEFT)
        self.port_var = tk.StringVar()
        self.port_dropdown = tk.OptionMenu(port_frame, self.port_var, "")
        self.port_dropdown.pack(side=tk.LEFT, padx=5)
        self.refresh_ports()
        tk.Button(port_frame, text="Refresh", command=self.refresh_ports).pack(side=tk.LEFT, padx=2)
        tk.Button(port_frame, text="Connect",  command=self.connect_serial).pack(side=tk.LEFT)

        self.canvas = tk.Canvas(self.root, width=CANVAS_SIZE, height=CANVAS_SIZE, bg='black', cursor="cross")
        self.canvas.pack(pady=10)
        self.canvas.bind("<B1-Motion>",      self.paint)
        self.canvas.bind("<ButtonRelease-1>", self.reset_brush)

        btn_frame = tk.Frame(self.root)
        btn_frame.pack(pady=5)
        tk.Button(btn_frame, text="Clear", command=self.clear_canvas, width=10).pack(side=tk.LEFT, padx=5)
        tk.Button(btn_frame, text="Send to FPGA", command=self.send_image, width=15, bg="green", fg="white").pack(side=tk.LEFT, padx=5)

        self.result_var = tk.StringVar(value="Prediction: --")
        tk.Label(self.root, textvariable=self.result_var, font=("Helvetica", 16, "bold")).pack(pady=8)
        self.hint_var = tk.StringVar(value="")
        tk.Label(self.root, textvariable=self.hint_var, font=("Helvetica", 10), fg="gray").pack()
        self.log_text = tk.Text(self.root, height=5, width=45, state=tk.DISABLED)
        self.log_text.pack(pady=5)

    def refresh_ports(self):
        ports = [p.device for p in serial.tools.list_ports.comports()]
        menu  = self.port_dropdown["menu"]
        menu.delete(0, "end")
        for port in ports:
            menu.add_command(label=port, command=lambda p=port: self.port_var.set(p))
        if ports:
            self.port_var.set(ports[0])

    def connect_serial(self):
        port = self.port_var.get()
        if not port: return
        try:
            if self.serial_port and self.serial_port.is_open:
                self.serial_port.close()
            self.serial_port = serial.Serial(port, BAUD_RATE, timeout=1)
            self.log(f"Connected to {port}")
            self.hint_var.set("Ready — draw a digit and press 'Send'.")
        except Exception as e:
            messagebox.showerror("Connection Error", str(e))

    def paint(self, event):
        x, y = event.x, event.y
        if self.last_x is not None and self.last_y is not None:
            self.canvas.create_line((self.last_x, self.last_y, x, y), fill='white', width=BRUSH_SIZE, capstyle=tk.ROUND, smooth=tk.TRUE)
            self.draw.line((self.last_x, self.last_y, x, y), fill=255, width=BRUSH_SIZE, joint="curve")
        self.last_x, self.last_y = x, y

    def reset_brush(self, event):
        self.last_x, self.last_y = None, None

    def clear_canvas(self):
        self.canvas.delete("all")
        self.image  = Image.new("L", (CANVAS_SIZE, CANVAS_SIZE), color=0)
        self.draw   = ImageDraw.Draw(self.image)
        self.result_var.set("Prediction: --")

    def process_image(self, img):
        bbox = img.getbbox()
        if bbox is None: return img.resize((28, 28), Image.Resampling.BILINEAR)
        cropped = img.crop(bbox)
        w, h = cropped.size
        if w > h: new_w, new_h = 20, max(1, int(20 * (h / w)))
        else: new_w, new_h = max(1, int(20 * (w / h))), 20
        resized = cropped.resize((new_w, new_h), Image.Resampling.BILINEAR)
        final_img = Image.new("L", (28, 28), "black")
        paste_x, paste_y = (28 - new_w) // 2, (28 - new_h) // 2
        final_img.paste(resized, (paste_x, paste_y))
        return final_img

    def send_image(self):
        if not self.serial_port or not self.serial_port.is_open:
            messagebox.showerror("Error", "Not connected to FPGA.")
            return

        img_centered = self.process_image(self.image)
        pixel_array  = np.array(img_centered, dtype=np.float32) / 255.0

        # FIX: Map [0.0, 1.0] → [-127, +127] to match the model's training distribution.
        # The model was trained with Normalize((0.5,), (0.5,)) which maps pixels to [-1,+1].
        # quantize_weights.py uses scale_input = 1/127, so INT8 range must be [-127, +127].
        # The old code sent [0, 127]: black pixels arrived as 0 instead of -127,
        # injecting a +127 DC offset into every neuron's dot product → wrong logits.
        int8_array   = np.clip(np.round(pixel_array * 254.0 - 127.0), -127, 127).astype(np.int8)
        
        # Convert int8 to uint8 (Two's Complement) for raw byte transmission
        uint8_array  = int8_array.view(np.uint8)
        flat_bytes   = uint8_array.tobytes()

        try:
            # Send exactly 784 bytes once. Sending more than once causes the
            # uart_bram_writer to reset bram_waddr to 0 and overwrite the input
            # BRAM while inference is already running → corrupted/random results.
            self.serial_port.write(flat_bytes)
            self.serial_port.flush()
            self.log(f"Sent {len(flat_bytes)} bytes to FPGA.")
            self.result_var.set("Image sent!")
        except Exception as e:
            self.log(f"TX Error: {e}")

    def log(self, msg):
        self.log_text.config(state=tk.NORMAL)
        self.log_text.insert(tk.END, msg + "\n")
        self.log_text.see(tk.END)
        self.log_text.config(state=tk.DISABLED)

if __name__ == "__main__":
    root = tk.Tk()
    app  = NeuroCoreHostGUI(root)
    root.mainloop()
