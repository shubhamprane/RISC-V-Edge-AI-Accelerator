/* test_full_inference.c - Full MNIST inference (2 layers) with Benchmarking */
#include <stdint.h>
#include "cop_mmio.h"

#define RESULT_ADDR    0x00001F00
#define PRED_CLASS     (*(volatile uint32_t*)(RESULT_ADDR + 0x00))
#define PRED_SCORE     (*(volatile int32_t*)(RESULT_ADDR + 0x04))
#define INFER_COUNT    (*(volatile uint32_t*)(RESULT_ADDR + 0x08))
#define CYCLES_TAKEN   (*(volatile uint32_t*)(RESULT_ADDR + 0x0C))

// Metrics for UART sender
#define HW_CYCLES_REG  (*(volatile uint32_t*)(COP_BASE + 0x02C))
#define SW_CYCLES_REG  (*(volatile uint32_t*)(COP_BASE + 0x030))

// Software Baseline from BENCHMARK_REPORT.md
#define SW_BASELINE_CYCLES 12852480

int main(void) {
    uint32_t count = 0;
    
    // Initial clear
    HW_CYCLES_REG = 0;
    SW_CYCLES_REG = 0;

    while (1) {
        // 1. Wait for hardware to start (triggered by UART receive)
        while (COP_STATUS == 0); 
        
        // 2. Wait for hardware to finish processing
        cop_wait();

        // 3. Capture Hardware-calculated cycles
        uint32_t hw_calc_cycles = HW_EXEC_CYCLES;
        count++;

        // 4. Perform Software ArgMax for host validation
        int32_t scores[10];
        scores[0] = COP_SCORE_0; scores[1] = COP_SCORE_1; scores[2] = COP_SCORE_2;
        scores[3] = COP_SCORE_3; scores[4] = COP_SCORE_4; scores[5] = COP_SCORE_5;
        scores[6] = COP_SCORE_6; scores[7] = COP_SCORE_7; scores[8] = COP_SCORE_8;
        scores[9] = COP_SCORE_9;

        int32_t max_score = scores[0];
        uint32_t max_idx = 0;
        for (int i = 1; i < 10; i++) {
            if (scores[i] > max_score) {
                max_score = scores[i];
                max_idx = i;
            }
        }

        // 5. Store results for memory-mapped verification
        PRED_CLASS  = max_idx;
        PRED_SCORE  = max_score;
        INFER_COUNT = count;
        CYCLES_TAKEN = hw_calc_cycles;

        // 6. Post exact calculation metrics to MMIO
        // IMPORTANT: Writing to SW_CYCLES_REG triggers the UART Log Sender in RTL
        HW_CYCLES_REG = hw_calc_cycles;
        for(volatile int d=0; d<100; d++); // Small gap
        SW_CYCLES_REG = SW_BASELINE_CYCLES;
        
        // 7. Large delay to prevent re-triggering while UART is busy
        // Sending 48 bytes at 115200 baud takes ~4.2ms. 
        // 1,000,000 loops at ~10MHz is plenty.
        for(volatile int i=0; i<1000000; i++);
    }
    return 0;
}
