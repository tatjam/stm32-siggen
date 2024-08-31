const std = @import("std");
const stm32u083 = @import("stm32u083.zig");

const periph = stm32u083.devices.STM32U083.peripherals;

pub fn export_vector_table() void {}

fn default_handler() callconv(.C) noreturn {
    while (true) {}
}

extern var __stack: anyopaque;

const vector_table: stm32u083.devices.STM32U083.VectorTable = .{
    .initial_stack_pointer = &__stack,
    .Reset = reset_handler,
};

comptime {
    @export(&reset_handler, .{ .name = "_start" });
    @export(&vector_table, .{
        .name = "vector_table",
        .section = ".isr_vector",
        .linkage = .strong,
    });
}

const run = @import("run.zig").run;

export fn reset_handler() callconv(.C) void {
    const StartupLocations = struct {
        extern var _sbss: u8;
        extern var _ebss: u8;
        extern var _sdata: u8;
        extern var _edata: u8;
        extern const _sidata: u8;
    };

    // Zero set bss
    {
        const bss_start: [*]u8 = @ptrCast(&StartupLocations._sbss);
        const bss_end: [*]u8 = @ptrCast(&StartupLocations._ebss);
        const bss_len = @intFromPtr(bss_end) - @intFromPtr(bss_start);
        @memset(bss_start[0..bss_len], 0);
    }

    // Copy changeable data from FLASH to RAM
    {
        const data_start: [*]u8 = @ptrCast(&StartupLocations._sdata);
        const data_end: [*]u8 = @ptrCast(&StartupLocations._edata);
        const data_len = @intFromPtr(data_end) - @intFromPtr(data_start);

        // Note that .data is defined > RAM AT > FLASH
        // so the addresses of _sdata and _edata are in RAM, but
        // _sidata = LOADADDR(.data) which gives the actual location in FLASH!
        const data_flash: [*]const u8 = @ptrCast(&StartupLocations._sidata);

        @memcpy(data_start[0..data_len], data_flash[0..data_len]);
    }

    run();
}
