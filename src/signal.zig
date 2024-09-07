// The signal generation logic "core" is here: Because a lot of different signals
// can be generated without "CPU intervention", we allow any of those (as long as they
// don't share pins), but only allow one "CPU-heavy" waveform out at once.

// sin may be run at any time as it's DMA + DAC (see details inside)

const stm32u083 = @import("hw/stm32u083.zig").devices.STM32U083;
pub const sin = @import("signal/sin.zig");
pub const noise = @import("signal/noise.zig");

const RCC = stm32u083.peripherals.RCC;

pub fn launch_sin(f: u32) !void {
    // Noise and sin are incompatible
    noise.stop();
    sin.stop();
    try sin.start(f);
}

pub fn launch_noise(rate: u32) !void {
    sin.stop();
    noise.stop();
    try noise.start(rate);
}

pub fn init() void {
    // Enable peripherals we use
    RCC.RCC_AHBENR.modify(.{
        .DMA1EN = @as(u1, 1),
    });
    RCC.RCC_APBENR1.modify(.{
        .TIM6EN = @as(u1, 1),
        .DAC1EN = @as(u1, 1),
    });
}
