/* bench_perf.c - Cycle-counter performance benchmark */
#include <stdint.h>
#include "cop_mmio.h"

#define BENCH_BASE    0x00001E00
#define BENCH_ENTRY(n) ((volatile uint32_t*)(BENCH_BASE + (n)*12))

typedef struct {
    uint32_t rows;
    uint32_t cols;
    uint32_t cycles;
} BenchResult;

static const BenchResult configs[] = {
    {1,   4,   0},
    {1,  16,   0},
    {1, 784,   0},
    {4, 784,   0},
    {8, 784,   0},
};
#define N_CONFIGS 5

int main(void) {
    for (int i = 0; i < N_CONFIGS; i++) {
        COP_L1_WT_BASE   = 0;
        COP_L1_BIAS_BASE = 0;
        COP_L1_ROWS      = configs[i].rows;
        COP_L1_COLS      = configs[i].cols;
        
        // Skip L2
        COP_L2_WT_BASE   = 0;
        COP_L2_BIAS_BASE = 0;
        COP_L2_ROWS      = 0;
        COP_L2_COLS      = 0;
        
        COP_INTER_SHIFT  = 11;

        uint32_t t0 = rdcycle();
        COP_START = 1;
        cop_wait();
        uint32_t t1 = rdcycle();

        volatile uint32_t* entry = BENCH_ENTRY(i);
        entry[0] = configs[i].rows;
        entry[1] = configs[i].cols;
        entry[2] = t1 - t0;
    }
    *((volatile uint32_t*)(BENCH_BASE + N_CONFIGS*12)) = 0xCAFECAFE;
    while(1);
    return 0;
}
