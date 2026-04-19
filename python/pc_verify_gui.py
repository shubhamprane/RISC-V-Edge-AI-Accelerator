import tkinter as tk
from PIL import Image, ImageDraw
import numpy as np
import os
from preprocess import preprocess_digit

# Configuration
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DATA_DIR = os.path.join(SCRIPT_DIR, "..", "data")
WEIGHTS_PATH = os.path.join(DATA_DIR, "weights.mem")
BIAS_PATH = os.path.join(DATA_DIR, "bias.mem")

def load_mem_packed(filename, total_bytes):
    """Loads a .mem file where 4 bytes are packed into a 32-bit little-endian hex word.
    
    export_to_mem packs as: word = (b3<<24)|(b2<<16)|(b1<<8)|b0
    So byte 0 is at bits [7:0] (little-endian).
    """
    data = []
    if not os.path.exists(filename):
        print(f"Error: {filename} not found.")
        return np.zeros(total_bytes, dtype=np.int8)
    
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('/'): continue
            try:
                word = int(line, 16)
                # Unpack little-endian: byte 0 at bits [7:0], byte 1 at [15:8], etc.
                for i in range(4):
                    val = (word >> (i*8)) & 0xFF
                    if val > 127: val -= 256
                    data.append(np.int8(val))
            except ValueError:
                continue
    return np.array(data[:total_bytes], dtype=np.int8)

def load_bias(filename, count):
    """Loads signed 32-bit hex values."""
    biases = []
    if not os.path.exists(filename):
        print(f"Error: {filename} not found.")
        return np.zeros(count, dtype=np.int32)
        
    with open(filename, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('/'): continue
            try:
                val = int(line, 16)
                if val > 0x7FFFFFFF: val -= 0x100000000
                biases.append(val)
                if len(biases) == count: break
            except ValueError:
                continue
    return np.array(biases, dtype=np.int32)

class PCVerifyApp:
    def __init__(self, root):
        self.root = root
        self.root.title("NeuroCore - PC Weight Verifier")
        
        # Load weights and biases
        print("Loading weights and biases...")
        self.HIDDEN = 128
        weights_flat = load_mem_packed(WEIGHTS_PATH, self.HIDDEN * 784 + 10 * self.HIDDEN)
        self.W1 = weights_flat[:self.HIDDEN * 784].reshape(self.HIDDEN, 784)
        self.W2 = weights_flat[self.HIDDEN * 784:].reshape(10, self.HIDDEN)
        
        all_biases = load_bias(BIAS_PATH, self.HIDDEN + 10)
        self.b1 = all_biases[:self.HIDDEN]
        self.b2 = all_biases[self.HIDDEN:]
        
        # Read config to get inter_shift
        self.inter_shift = 11
        config_path = os.path.join(DATA_DIR, "config.txt")
        if os.path.exists(config_path):
            with open(config_path, 'r') as f:
                for line in f:
                    if line.startswith('inter_shift='):
                        self.inter_shift = int(line.strip().split('=')[1])
                        
        print(f"Weights loaded: W1 {self.W1.shape}, W2 {self.W2.shape}, inter_shift={self.inter_shift}")
        
        self.canvas_size = 280
        self.pixel_size = 28
        
        # Left side: Drawing
        self.draw_frame = tk.Frame(root)
        self.draw_frame.pack(side=tk.LEFT, padx=10, pady=10)
        
        self.canvas = tk.Canvas(self.draw_frame, width=self.canvas_size, height=self.canvas_size, bg='black')
        self.canvas.pack()
        
        # PIL image for backend processing
        self.image = Image.new("L", (self.canvas_size, self.canvas_size), 0)
        self.draw = ImageDraw.Draw(self.image)
        
        self.canvas.bind("<B1-Motion>", self.paint)
        
        self.btn_frame = tk.Frame(self.draw_frame)
        self.btn_frame.pack(fill=tk.X)
        
        self.btn_predict = tk.Button(self.btn_frame, text="Predict (PC)", command=self.predict, bg="lightblue")
        self.btn_predict.pack(side=tk.LEFT, fill=tk.X, expand=True)
        
        self.btn_clear = tk.Button(self.btn_frame, text="Clear", command=self.clear_canvas)
        self.btn_clear.pack(side=tk.RIGHT, fill=tk.X, expand=True)
        
        # Right side: Results
        self.result_frame = tk.Frame(root)
        self.result_frame.pack(side=tk.RIGHT, padx=10, pady=10, fill=tk.Y)
        
        self.result_title = tk.Label(self.result_frame, text="Prediction Scores", font=("Helvetica", 12, "bold"))
        self.result_title.pack()
        
        self.score_labels = []
        for i in range(10):
            lbl = tk.Label(self.result_frame, text=f"Digit {i}: ---", font=("Courier", 10))
            lbl.pack(anchor=tk.W)
            self.score_labels.append(lbl)
            
        self.final_pred = tk.Label(self.result_frame, text="Prediction: ?", font=("Helvetica", 16, "bold"), fg="blue")
        self.final_pred.pack(pady=10)

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
        for i in range(10):
            self.score_labels[i].config(text=f"Digit {i}: ---", fg="black")
        self.final_pred.config(text="Prediction: ?", fg="blue")

    def predict(self):
        # 1. Preprocess image: center, normalize, scale to match MNIST and hardware
        flat_input = preprocess_digit(self.image, self.canvas_size, 28)
        # 2. Perform Inference matching hardware
        l1_out = np.dot(self.W1.astype(np.int32), flat_input.astype(np.int32)) + self.b1
        l1_relu = np.maximum(0, l1_out)
        l1_scaled = (l1_relu >> self.inter_shift).clip(0, 127).astype(np.uint8)
        
        scores = np.dot(self.W2.astype(np.int32), l1_scaled.astype(np.int32)) + self.b2
        # 4. Update UI
        predicted_class = np.argmax(scores)
        
        for i in range(10):
            color = "red" if i == predicted_class else "black"
            self.score_labels[i].config(text=f"Digit {i}: {scores[i]:10d}", fg=color)
            
        self.final_pred.config(text=f"Prediction: {predicted_class}")

if __name__ == "__main__":
    root = tk.Tk()
    app = PCVerifyApp(root)
    root.mainloop()
