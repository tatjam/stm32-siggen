ENTRY(reset_handler)

MEMORY
{
	RAM (xrw) 	: ORIGIN = 0x20000000, LENGTH = 40K
	FLASH (rx)     : ORIGIN = 0x8000000,  LENGTH = 256K
}

PROVIDE(__stack = ORIGIN(RAM) + LENGTH(RAM));

SECTIONS {
	.isr_vector : 
	{
		. = ALIGN(4);
		KEEP(*(.isr_vector))
		. = ALIGN(4);
	}

	.text :
	{
		. = ALIGN(4);
		*(.text)
		*(.text*)
		*(.glue_7)
		*(.glue_7t)
		. = ALIGN(4);
	} > FLASH

	.rodata :
	{
		. = ALIGN(4);
		*(.rodata)
		*(.rodata*)
		. = ALIGN(4);
	} > FLASH

	/* Stack unwinding stuff (ARM magic) */
	.ARM.extab   : { *(.ARM.extab* .gnu.linkonce.armextab.*) } >FLASH
	.ARM : 
	{
		__exidx_start = .;
    	*(.ARM.exidx*)
    	__exidx_end = .;
	} >FLASH

	_sidata = LOADADDR(.data);

	.data : 
	{
		. = ALIGN(4);
		/* Start of changeable data, to copy at startup into RAM */
		_sdata = .;
		*(.data)
		*(.data*)
		*(COMMON)

		. = ALIGN(4);
		/* End of changeable data */
		_edata = .;
	} > RAM AT > FLASH

	. = ALIGN(4);
	.bss : 
	{
		/* Start of zero initialized data, to be set by the program at start */
		_sbss = .;
		*(.bss)
		*(.bss*)
		*(COMMON)

		. = ALIGN(4);
		/* End of zero initialized data */
		_ebss = .;
	} > RAM

	.ARM.attributes 0 : { *(.ARM.attributes) }
}
