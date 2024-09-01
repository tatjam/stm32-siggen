// This file implements the connection to the computer (through the STLink)
// In the future this could be expanded to use tinyusb or similar, although the
// NUCLEO board doesn't have a USB port connected to the MCU!
// Of course, using the STLink as a serial device is not optimal, but we don't
// move big ammounts of data anyway...

// By default on the NUCLEO board USART2 (PA2/PA3) is used as VCP (Virtual COM port),
// so we use it just for this purpose :)

const stm32u083 = @import("stm32u083.zig");
const periph = stm32u083.devices.STM32U083.peripherals;

pub fn init_serial() !void {
    periph.RCC.RCC_APBENR1.modify(.{
        .LPUART2EN = @as(u1, 0x1),
    });
}
