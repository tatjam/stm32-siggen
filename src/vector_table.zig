const stm32u083 = @import("stm32u083.zig");

extern var __stack: anyopaque;

const vector_table: stm32u083.devices.STM32U083.VectorTable = .{
    .initial_stack_pointer = &__stack,
    .Reset = @import("main.zig").reset_handler,
    .USART2_LPUART2 = @import("serial.zig").interrupt_handler,
};

comptime {
    @export(&vector_table, .{
        .name = "vector_table",
        .section = ".isr_vector",
        .linkage = .strong,
    });
}
