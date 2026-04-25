/* bench_inference.c - Full MNIST inference (2 layers) without delay */
#include <stdint.h>
#include "cop_mmio.h"

#define RESULT_ADDR    0x00001F00
#define CYCLES_TAKEN   (*(volatile uint32_t*)(RESULT_ADDR + 0x0C))

void run_inference(void) {
    COP_L1_WT_BASE   = 0;
    COP_L1_BIAS_BASE = 0;
    COP_L1_ROWS      = 128;
    COP_L1_COLS      = 128;

    COP_L2_WT_BASE   = 4096; // 128*128/4 words? No, weight BRAM is indexed by words. 
                             // Wait, weights.mem is bytes. 128*128 = 16384 bytes.
                             // 16384 / 4 = 4096 words.
    COP_L2_BIAS_BASE = 128;
    COP_L2_ROWS      = 10;
    COP_L2_COLS      = 128;
    
    COP_INTER_SHIFT  = 11;

    COP_START        = 1;
    cop_wait();
}

int main(void) {
    uint32_t t0 = rdcycle();
    run_inference();
    uint32_t t1 = rdcycle();

    CYCLES_TAKEN = t1 - t0;
    
    // Done signal for testbench
    *((volatile uint32_t*)(RESULT_ADDR + 0x10)) = 0xDEADEAD;
    
    while(1);
    return 0;
}
