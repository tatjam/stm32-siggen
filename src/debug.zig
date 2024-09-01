const std = @import("std");

const print_buf: [128]u8 = undefined;

pub fn debug_print(comptime fmt: []const u8, args: anytype) !void {
    const nbuf = try std.fmt.bufPrint(print_buf, fmt, args);

    // Write thorugh STLink to computer
    _ = nbuf; // autofix
}
