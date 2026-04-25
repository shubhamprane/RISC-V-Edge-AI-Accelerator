/* test_layer2.c - Configure and run Layer 2 */
#include <stdint.h>
#include "cop_mmio.h"

int main(void) {
    // Zero out Layer 1 to skip directly or minimize impact
    COP_L1_WT_BASE   = 0;
    COP_L1_BIAS_BASE = 0;
    COP_L1_ROWS      = 8; // Min rows for 1 tile
    COP_L1_COLS      = 8; // Min cols

    // Configure Layer 2
    COP_L2_WT_BASE   = 25088; 
    COP_L2_BIAS_BASE = 128;
    COP_L2_ROWS      = 10;
    COP_L2_COLS      = 128;
    
    COP_INTER_SHIFT  = 11;

    // Start coprocessor
    uint32_t t0 = rdcycle();
    COP_START = 1;
    cop_wait();
    uint32_t t1 = rdcycle();

    // Store cycle count in an unused register area for checking
    (*(volatile uint32_t*)(COP_BASE + 0x1F04)) = (t1 - t0);

    while(1);
    return 0;
}
