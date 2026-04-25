import sys
import struct

def bin2hex(bin_file, hex_file, size_words=16384):
    try:
        with open(bin_file, 'rb') as f:
            data = f.read()
    except FileNotFoundError:
        data = b''
        
    words = []
    for i in range(0, len(data), 4):
        chunk = data[i:i+4]
        if len(chunk) < 4:
            chunk += b'\x00' * (4 - len(chunk))
        # Unpack as little endian 32-bit integer
        word = struct.unpack('<I', chunk)[0]
        words.append(f"{word:08x}\n")
    
    # Fill remaining memory with zeros (NOP is 00000013 for imem, but 00000000 is safer/cleaner for dmem and empty regions)
    # Actually for instruction memory, executing 0x00000000 is an illegal instruction trap if not set up, 
    # but we have an infinite loop at the end of our code.
    while len(words) < size_words:
        words.append("00000000\n")
        
    with open(hex_file, 'w') as f:
        f.writelines(words)
    print(f"[HEX GEN] Generated {hex_file} ({len(data)} bytes -> {len(words)} words)")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python elf2hex.py <input.bin> <output.hex>")
        sys.exit(1)
    bin2hex(sys.argv[1], sys.argv[2])
