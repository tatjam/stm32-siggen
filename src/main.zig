const std = @import("std");

comptime {
    @import("startup.zig").export_start_symbol();
}

export fn main() callconv(.C) noreturn {
    while (true) {}
}
