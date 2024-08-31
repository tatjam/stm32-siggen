const std = @import("std");

extern fn main() noreturn;

pub fn reset_handler() callconv(.C) noreturn {
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

    main();
}

pub fn export_start_symbol() void {
    @export(&reset_handler, .{ .name = "_start" });
}
