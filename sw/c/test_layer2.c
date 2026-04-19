/* test_layer2.c - 2-layer inference flow */
#include <stdint.h>
#include "cop_mmio.h"

#define RESULT_ADDR   0x00001F00
#define L1_DONE_FLAG  (*(volatile uint32_t*)(RESULT_ADDR + 0x00))
#define L2_DONE_FLAG  (*(volatile uint32_t*)(RESULT_ADDR + 0x04))

void main(void) {
    // --- Layer 1: 784 → 10 with ReLU ---
    COP_IN_BASE   = 0;
    COP_WT_BASE   = 0;
    COP_OUT_BASE  = 0;
    COP_BIAS_BASE = 0;
    COP_ROWS      = 10;
    COP_COLS      = 784;
    COP_RELU_EN   = 1;
    COP_START     = 1;
    cop_wait();
    L1_DONE_FLAG  = 0x11110001;

    // --- Layer 2: 10 → 10 ---
    COP_IN_BASE   = 0;   // Recycle output BRAM
    COP_WT_BASE   = 0;
    COP_OUT_BASE  = 0;
    COP_BIAS_BASE = 0;
    COP_ROWS      = 10;
    COP_COLS      = 10;
    COP_RELU_EN   = 0;
    COP_START     = 1;
    cop_wait();
    L2_DONE_FLAG  = 0x22220002;

    while(1);
}
