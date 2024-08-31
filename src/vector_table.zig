const std = @import("std");
const stm32u083 = @import("stm32u083.zig");

pub fn export_vector_table() void {
    @export(&vector_table, .{
        .name = "vector_table",
        .section = ".isr_vector",
        .linkage = .strong,
    });
}

fn default_handler() callconv(.C) noreturn {
    while (true) {}
}

extern var __stack: anyopaque;

const vector_table: stm32u083.devices.STM32U083.VectorTable = .{
    .initial_stack_pointer = &__stack,
    .Reset = @import("startup.zig").reset_handler,
};
