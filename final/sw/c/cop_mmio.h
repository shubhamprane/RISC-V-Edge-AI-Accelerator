#ifndef COP_MMIO_H
#define COP_MMIO_H

#include <stdint.h>

#define COP_BASE           0xC0000000UL

/* Control & Status */
#define COP_START          (*(volatile uint32_t*)(COP_BASE + 0x000))
#define COP_STATUS         (*(volatile uint32_t*)(COP_BASE + 0x004))

/* Layer 1 Configuration */
#define COP_L1_WT_BASE     (*(volatile uint32_t*)(COP_BASE + 0x008))
#define COP_L1_BIAS_BASE   (*(volatile uint32_t*)(COP_BASE + 0x00C))
#define COP_L1_ROWS        (*(volatile uint32_t*)(COP_BASE + 0x010))
#define COP_L1_COLS        (*(volatile uint32_t*)(COP_BASE + 0x014))

/* Layer 2 Configuration */
#define COP_L2_WT_BASE     (*(volatile uint32_t*)(COP_BASE + 0x018))
#define COP_L2_BIAS_BASE   (*(volatile uint32_t*)(COP_BASE + 0x01C))
#define COP_L2_ROWS        (*(volatile uint32_t*)(COP_BASE + 0x020))
#define COP_L2_COLS        (*(volatile uint32_t*)(COP_BASE + 0x024))

/* Intermediate Scaling */
#define COP_INTER_SHIFT    (*(volatile uint32_t*)(COP_BASE + 0x028))

/* Profiling */
#define CYCLE_COUNT        (*(volatile uint32_t*)(COP_BASE + 0x200))
#define HW_EXEC_CYCLES     (*(volatile uint32_t*)(COP_BASE + 0x330))

/* Output Scores (10 classes x 32-bit INT32) */
#define COP_SCORE_0        (*(volatile int32_t*)(COP_BASE + 0x300))
#define COP_SCORE_1        (*(volatile int32_t*)(COP_BASE + 0x304))
#define COP_SCORE_2        (*(volatile int32_t*)(COP_BASE + 0x308))
#define COP_SCORE_3        (*(volatile int32_t*)(COP_BASE + 0x30C))
#define COP_SCORE_4        (*(volatile int32_t*)(COP_BASE + 0x310))
#define COP_SCORE_5        (*(volatile int32_t*)(COP_BASE + 0x314))
#define COP_SCORE_6        (*(volatile int32_t*)(COP_BASE + 0x318))
#define COP_SCORE_7        (*(volatile int32_t*)(COP_BASE + 0x31C))
#define COP_SCORE_8        (*(volatile int32_t*)(COP_BASE + 0x320))
#define COP_SCORE_9        (*(volatile int32_t*)(COP_BASE + 0x324))

static inline uint32_t rdcycle(void) {
    return CYCLE_COUNT;
}

static inline void cop_wait(void) {
    /* Wait while STATUS != 0 (cop_busy is high) */
    while (COP_STATUS != 0);
}

#endif // COP_MMIO_H
