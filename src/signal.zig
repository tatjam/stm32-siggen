// The signal generation logic "core" is here: Because a lot of different signals
// can be generated without "CPU intervention", we allow any of those (as long as they
// don't share pins), but only allow one "CPU-heavy" waveform out at once.

// sin may be run at any time as it's DMA + DAC (see details inside)

const stm32u083 = @import("hw/stm32u083.zig").devices.STM32U083;
pub const sin = @import("signal/sin.zig");
pub const noise = @import("signal/noise.zig");
pub const pwm = @import("signal/pwm.zig");

const RCC = stm32u083.peripherals.RCC;
const GPIOA = stm32u083.peripherals.GPIOA;
const GPIOB = stm32u083.peripherals.GPIOB;

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

pub fn launch_pwm(settings: [2]pwm.TimerSettings) !void {
    pwm.stop();
    try pwm.start(settings);
}

pub fn init() void {
    // Enable peripherals we use
    RCC.RCC_IOPENR.modify(.{
        .GPIOBEN = @as(u1, 1), // Enable
    });

    RCC.RCC_AHBENR.modify(.{
        .DMA1EN = @as(u1, 1),
    });
    RCC.RCC_APBENR1.modify(.{
        .TIM6EN = @as(u1, 1),
        .DAC1EN = @as(u1, 1),
    });
    RCC.RCC_APBENR1.modify(.{
        .TIM2EN = @as(u1, 1),
        .TIM3EN = @as(u1, 1),
    });

    // Setup TIM2 and TIM3 outputs

    // Alternate functions

    GPIOA.GPIOA_MODER.modify(.{
        .MODE0 = @as(u2, 0b10), // Special purpose mode
    });
    GPIOB.GPIOB_MODER.modify(.{
        .MODE0 = @as(u2, 0b10), // Special purpose mode
        .MODE4 = @as(u2, 0b10), // Special purpose mode
        .MODE10 = @as(u2, 0b10), // Special purpose mode
    });

    GPIOA.GPIOA_AFRL.modify(.{
        .AFSEL0 = @as(u4, 1), // TIM2_CH1
    });

    GPIOB.GPIOB_AFRL.modify(.{
        .AFSEL0 = @as(u4, 2), // TIM3_CH3
        .AFSEL4 = @as(u4, 2), // TIM3_CH1
    });

    GPIOB.GPIOB_AFRH.modify(.{
        .AFSEL10 = @as(u4, 1), // TIM2_CH3
    });

    // Speed
    GPIOA.GPIOA_OSPEEDR.modify(.{
        .OSPEED0 = @as(u2, 0b11),
    });
    GPIOB.GPIOB_OSPEEDR.modify(.{
        .OSPEED0 = @as(u2, 0b11),
        .OSPEED4 = @as(u2, 0b11),
        .OSPEED10 = @as(u2, 0b11),
    });
}
