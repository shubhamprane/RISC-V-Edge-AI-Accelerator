#ifndef COP_MMIO_H
#define COP_MMIO_H

#define COP_BASE        0xC0000000UL
#define COP_START       (*(volatile uint32_t*)(COP_BASE + 0x00))
#define COP_STATUS      (*(volatile uint32_t*)(COP_BASE + 0x04))
#define COP_IN_BASE     (*(volatile uint32_t*)(COP_BASE + 0x08))
#define COP_WT_BASE     (*(volatile uint32_t*)(COP_BASE + 0x0C))
#define COP_OUT_BASE    (*(volatile uint32_t*)(COP_BASE + 0x10))
#define COP_ROWS        (*(volatile uint32_t*)(COP_BASE + 0x14))
#define COP_COLS        (*(volatile uint32_t*)(COP_BASE + 0x18))
#define COP_BIAS_BASE   (*(volatile uint32_t*)(COP_BASE + 0x1C))
#define COP_RELU_EN     (*(volatile uint32_t*)(COP_BASE + 0x24))
#define UART_RX_STATUS  (*(volatile uint32_t*)(COP_BASE + 0x100))
#define CYCLE_COUNT     (*(volatile uint32_t*)(COP_BASE + 0x200))

static inline uint32_t rdcycle(void) {
    return CYCLE_COUNT;
}

static inline void cop_wait(void) {
    while (COP_STATUS & 0x1);
}
#endif
