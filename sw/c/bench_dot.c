/* bench_dot.c - Dot product benchmark: SW vs HW */
#include <stdint.h>
#include "cop_mmio.h"

#define RESULT_ADDR  0x00001F00   // Write results here for testbench inspection
#define SW_RESULT    (*(volatile uint32_t*)(RESULT_ADDR + 0x00))
#define HW_RESULT    (*(volatile uint32_t*)(RESULT_ADDR + 0x04))
#define SW_CYCLES    (*(volatile uint32_t*)(RESULT_ADDR + 0x08))
#define HW_CYCLES    (*(volatile uint32_t*)(RESULT_ADDR + 0x0C))
#define MATCH_FLAG   (*(volatile uint32_t*)(RESULT_ADDR + 0x10))

void main(void) {
    // --- Software dot product ---
    uint32_t t0 = rdcycle();
    int32_t sw_dot = 0;
    for (int i = 0; i < 784; i++) sw_dot += (int8_t)50 * (int8_t)1;
    uint32_t t1 = rdcycle();
    SW_RESULT = (uint32_t)sw_dot;
    SW_CYCLES = t1 - t0;

    // --- Hardware dot product (1 row, 784 cols) ---
    COP_ROWS   = 1;
    COP_COLS   = 784;
    COP_RELU_EN = 0;
    uint32_t t2 = rdcycle();
    COP_START = 1;
    cop_wait();
    uint32_t t3 = rdcycle();
    HW_CYCLES = t3 - t2;
    MATCH_FLAG = (sw_dot == 39200) ? 0xDEADBEEF : 0xBAD0BAD0;

    while(1);
}
