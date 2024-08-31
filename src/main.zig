const std = @import("std");
const stm32u083 = @import("stm32u083.zig");

const periph = stm32u083.devices.STM32U083.peripherals;

comptime {
    @import("startup.zig").export_start_symbol();
}

export fn main() callconv(.C) noreturn {
    // LED at PA 5
    periph.RCC.RCC_IOPENR.modify(.{
        .GPIOAEN = @as(u1, 0x01), // Enable
    });

    periph.GPIOA.GPIOA_MODER.modify(.{
        .MODE5 = @as(u2, 0x1), // General purpose output
    });

    while (true) {
        const val = periph.GPIOA.GPIOA_ODR.read().OD5;
        const nval: u1 = if (val == 0) 1 else 0;
        periph.GPIOA.GPIOA_ODR.modify(.{
            .OD5 = nval,
        });
        for (0..100000) |a| {
            _ = a;
        }
    }
}
