const std = @import("std");
const stm32u083 = @import("hw/stm32u083.zig");
const serial = @import("serial.zig");

const periph = stm32u083.devices.STM32U083.peripherals;

// Zig settings
pub const std_options: std.Options = .{
    .logFn = serial.serial_log,
};

// Override panic so we can actually debug Zig errors
// Obviously, this depends on serial not being borked. But that's pretty rare
pub fn panic(msg: []const u8, trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    _ = ret_addr; // autofix
    _ = trace; // autofix

    std.log.err("panic: {s}", .{msg});

    // Thx microzig
    var stk_idx: usize = 0;
    var iter = std.debug.StackIterator.init(@returnAddress(), null);
    while (iter.next()) |addr| : (stk_idx += 1) {
        std.log.err("{d: >3}: 0x{X:0>8}", .{ stk_idx, addr });
    }

    // Disable interrupts

    while (true) {
        @breakpoint();
    }
}

comptime {
    @export(&reset_handler, .{ .name = "_start" });
    _ = @import("vector_table.zig");
}

const run = @import("run.zig").run;

// The callconv(.C) MAY be unnecesary, not sure...
// (The function doesn't take arguments nor return them, so shouldn't matter...)
pub fn reset_handler() callconv(.C) void {
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
