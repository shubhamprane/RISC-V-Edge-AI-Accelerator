OUTPUT_ARCH( "riscv" )
ENTRY( _start )
MEMORY
{
    imem (rx)  : ORIGIN = 0x00000000, LENGTH = 4K
    dmem (rwx) : ORIGIN = 0x00001000, LENGTH = 4K
}
SECTIONS
{
    .text : { *(.text.init) *(.text*) } > imem
    .data : { *(.data*) *(.rodata*) } > dmem
    .bss  : { *(.bss*) } > dmem
    _stack_top = ORIGIN(dmem) + LENGTH(dmem);
}
