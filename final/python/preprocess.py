"""
MNIST-style preprocessing for hand-drawn digit images.
Centers and normalizes the drawn digit to match MNIST format.
"""
import numpy as np
from PIL import Image

def preprocess_digit(pil_image, canvas_size=280, target_size=28):
    """
    Preprocess a hand-drawn digit image to match MNIST format:
    1. Resize to target_size x target_size
    2. Threshold to remove noise
    3. Center the digit by center-of-mass (MNIST-style)
    4. Scale to [0, 127] for hardware (pixel / 2)
    
    Args:
        pil_image: PIL Image (grayscale, canvas_size x canvas_size)
        canvas_size: size of the drawing canvas
        target_size: output size (28 for MNIST)
    
    Returns:
        flat_data: numpy array of shape (784,) with uint8 values [0, 127]
    """
    # 1. Resize to 28x28
    img = pil_image.resize((target_size, target_size), Image.Resampling.LANCZOS)
    pixels = np.array(img, dtype=np.float32)
    
    # 2. Threshold to clean up anti-aliasing noise
    pixels[pixels < 30] = 0
    
    # 3. If the image is blank, return zeros
    if pixels.max() == 0:
        return np.zeros(target_size * target_size, dtype=np.uint8)
    
    # 4. Find bounding box of the digit
    rows = np.any(pixels > 0, axis=1)
    cols = np.any(pixels > 0, axis=0)
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    
    # 5. Crop the digit region
    cropped = pixels[rmin:rmax+1, cmin:cmax+1]
    
    # 6. Fit into a 20x20 box (MNIST standard) preserving aspect ratio
    h, w = cropped.shape
    target_box = 20
    scale = min(target_box / h, target_box / w)
    new_h, new_w = int(h * scale), int(w * scale)
    new_h = max(new_h, 1)
    new_w = max(new_w, 1)
    
    cropped_pil = Image.fromarray(cropped.astype(np.uint8))
    resized = cropped_pil.resize((new_w, new_h), Image.Resampling.LANCZOS)
    resized_arr = np.array(resized, dtype=np.float32)
    
    # 7. Place in center of 28x28 using center-of-mass (MNIST-style)
    result = np.zeros((target_size, target_size), dtype=np.float32)
    
    # Calculate center of mass of the resized digit
    total_mass = resized_arr.sum()
    if total_mass > 0:
        cy = np.sum(np.arange(new_h).reshape(-1, 1) * resized_arr) / total_mass
        cx = np.sum(np.arange(new_w).reshape(1, -1) * resized_arr) / total_mass
    else:
        cy, cx = new_h / 2, new_w / 2
    
    # Place so that center of mass is at (14, 14) - center of 28x28
    offset_y = int(round(14 - cy))
    offset_x = int(round(14 - cx))
    
    # Clip to valid range
    src_y_start = max(0, -offset_y)
    src_x_start = max(0, -offset_x)
    dst_y_start = max(0, offset_y)
    dst_x_start = max(0, offset_x)
    
    copy_h = min(new_h - src_y_start, target_size - dst_y_start)
    copy_w = min(new_w - src_x_start, target_size - dst_x_start)
    
    if copy_h > 0 and copy_w > 0:
        result[dst_y_start:dst_y_start+copy_h, dst_x_start:dst_x_start+copy_w] = \
            resized_arr[src_y_start:src_y_start+copy_h, src_x_start:src_x_start+copy_w]
    
    # 8. Normalize to [0, 255] then scale to [0, 127] for hardware
    if result.max() > 0:
        result = (result / result.max()) * 255.0
    
    hw_data = (result / 2).astype(np.uint8)
    return hw_data.flatten()
