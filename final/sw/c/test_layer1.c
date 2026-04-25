/* test_layer1.c - Configure and run Layer 1 only */
#include <stdint.h>
#include "cop_mmio.h"

int main(void) {
    // Configure Layer 1
    COP_L1_WT_BASE   = 0;
    COP_L1_BIAS_BASE = 0;
    COP_L1_ROWS      = 128;
    COP_L1_COLS      = 784;

    // Zero out Layer 2 to simulate a single-layer run
    COP_L2_WT_BASE   = 0;
    COP_L2_BIAS_BASE = 0;
    COP_L2_ROWS      = 0;
    COP_L2_COLS      = 0;
    
    COP_INTER_SHIFT  = 11;

    // Start coprocessor
    uint32_t t0 = rdcycle();
    COP_START = 1;
    cop_wait();
    uint32_t t1 = rdcycle();

    // Store cycle count in an unused register area for checking
    (*(volatile uint32_t*)(COP_BASE + 0x1F00)) = (t1 - t0);

    while(1);
    return 0;
}
