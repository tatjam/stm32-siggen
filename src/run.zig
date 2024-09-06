const std = @import("std");
const stm32u083 = @import("hw/stm32u083.zig");
const periph = stm32u083.devices.STM32U083.peripherals;

const clock = @import("clock.zig");
const serial = @import("serial.zig");
const sin = @import("signal/sin.zig");

pub fn run() void {
    clock.setup();
    serial.init_serial();
    sin.init();

    // LED at PA 5
    periph.GPIOA.GPIOA_MODER.modify(.{
        .MODE5 = @as(u2, 0x1), // General purpose output
    });

    while (true) {
        serial.task_receive();
    }
}
