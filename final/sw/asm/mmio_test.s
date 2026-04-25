# sw/asm/mmio_test.s - Assembly smoke test for MMIO
.section .text.init
.globl _start

_start:
    # Set t0 to COP_BASE (0xC0000000)
    lui t0, 0xC0000
    
    # Write 128 to L1_ROWS (offset 0x010)
    li t1, 128
    sw t1, 0x010(t0)
    
    # Write 784 to L1_COLS (offset 0x014)
    li t2, 784
    sw t2, 0x014(t0)
    
    # Read them back (just to verify in simulation if needed)
    lw t3, 0x010(t0)
    lw t4, 0x014(t0)
    
    # Trigger coprocessor (write 1 to START, offset 0x000)
    li t5, 1
    sw t5, 0x000(t0)
    
wait_loop:
    # Read STATUS (offset 0x004)
    lw t6, 0x004(t0)
    bnez t6, wait_loop
    
done:
    j done
