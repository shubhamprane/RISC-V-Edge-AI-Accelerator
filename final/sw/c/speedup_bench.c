/* speedup_bench.c - CPU vs. Hardware Accelerator Benchmark */
#include <stdint.h>
#include "cop_mmio.h"

#define RESULT_ADDR    0x00001F00
#define HW_CYCLES      (*(volatile uint32_t*)(RESULT_ADDR + 0x00))
#define SW_CYCLES      (*(volatile uint32_t*)(RESULT_ADDR + 0x04))

// We use 128x128 for a balanced simulation time
#define ROWS 128
#define COLS 128

// Mock pointers to BRAM (in reality, data is already in BRAM)
// We'll just read from the BRAM addresses to simulate SW overhead
volatile int8_t*   input_ptr  = (volatile int8_t*)0x00001000; 
volatile int8_t*   weight_ptr = (volatile int8_t*)0x00002000; // Simplified for bench

void run_hardware_bench() {
    COP_L1_WT_BASE   = 0;
    COP_L1_BIAS_BASE = 0;
    COP_L1_ROWS      = 128;
    COP_L1_COLS      = 784;

    COP_L2_WT_BASE   = 25088; 
    COP_L2_BIAS_BASE = 128;
    COP_L2_ROWS      = 10;
    COP_L2_COLS      = 128;
    
    COP_INTER_SHIFT  = 11;

    COP_START        = 1;
    COP_START        = 0; // Clear immediately to prevent re-trigger
    cop_wait();
}

// Volatile sink to prevent dead-code elimination under -O2
volatile int32_t sw_bench_sink;

// Pure Software Implementation of a Dot Product
void run_software_bench() {
    int32_t sum = 0;
    // We simulate 1 row of Layer 1 (784 MACs)
    for (int c = 0; c < 784; c++) {
        sum += input_ptr[c] * weight_ptr[c];
    }
    sw_bench_sink = sum;  // Force compiler to keep the loop
}

int main(void) {
    uint32_t t0, t1;

    // 1. Benchmark Hardware
    t0 = rdcycle();
    run_hardware_bench();
    t1 = rdcycle();
    HW_CYCLES = t1 - t0;

    // 2. Benchmark Software (scaled to full 128 rows of Layer 1)
    t0 = rdcycle();
    run_software_bench();
    t1 = rdcycle();
    SW_CYCLES = (t1 - t0) * 128; 

    // 3. Post results to MMIO for UART logging
    *((volatile uint32_t*)(COP_BASE + 0x02C)) = HW_CYCLES;
    *((volatile uint32_t*)(COP_BASE + 0x030)) = SW_CYCLES;

    // Signal completion
    *((volatile uint32_t*)(RESULT_ADDR + 0x10)) = 0xDEADEAD;
    
    while(1);
    return 0;
}
