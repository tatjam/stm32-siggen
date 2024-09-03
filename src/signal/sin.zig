// Sine wave (fairly coarse frequency, prioritizes harmonic purity) generation using DAC
// NOTE: DMA1 channel 0 is reserved for this purpose
// NOTE: TIM6 is reserved for this purpose
// TODO: We may be bandwidth limited by the settling time, check on oscilloscope
// (This is kind of future proofing for other devices which have more than one DAC)

const std = @import("std");
const assert = std.debug.assert;

const stm32u083 = @import("../hw/stm32u083.zig");
const DMA = stm32u083.devices.STM32U083.peripherals.DMA1;
const TIM = stm32u083.devices.STM32U083.peripherals.TIM6;

// The DAC is limited to 1Msps, we have sinewaves of:
// N Samples, max freq (kHz)
// 8, 125
// 16, 62.5
// 32, 31.25
// 64, 15.525
// 128, 7.8125
// Lower frequencies are achieved by changing the timer
// (Obviously, the high frequency cases will result in heavy distortion)

// Generates DC offset sine data that ranges in [0, 1]
fn generate_sine_data_f64(comptime n: usize) [n]comptime_float {
    const out: [n]comptime_float = undefined;

    for (0..n) |idx| {
        const idxf: comptime_float = @floatFromInt(idx);
        // From 0 to nearly 1
        const prog = idxf / @as(comptime_float, @floatFromInt(n));
        out[idx] = 0.5 * (std.math.sin(prog * 2.0 * std.math.pi) + 1.0);
    }

    return out;
}

// Data is stored in the lowest 12 bits of a 16 bit word
fn convert_data_to_dac_format(comptime n: usize, comptime data: [n]comptime_float) [n]u16 {
    const out: [n]u16 = undefined;
    for (data, 0..) |dat, idx| {
        // The binary number is the maximum 12 bit value possible
        // (Clearly, the product of a number in (0, 1) with it must fit in 16 bits!)
        out[idx] = @intFromFloat(dat * @as(comptime_float, @floatFromInt(0b1111_1111_1111)));
        if (comptime out[idx] & 0b1111_0000_0000_0000 != 0) {
            @compileError("Somehow we overflowed the 12 bits!");
        }
    }
    return out;
}

fn generate_sine_data(comptime n: usize) [n]u16 {
    return convert_data_to_dac_format(n, generate_sine_data(n));
}

// This is all generated at comptime
pub const sine_8_data: [8]u16 = generate_sine_data(8);
pub const sine_16_data: [16]u16 = generate_sine_data(16);
pub const sine_32_data: [32]u16 = generate_sine_data(32);
pub const sine_64_data: [64]u16 = generate_sine_data(64);
pub const sine_128_data: [128]u16 = generate_sine_data(128);

const dma_buffer: [128]u16 = undefined;

// Launches a sine generator given frequency in hertz that
// best approximates this frequency on the output with
// maximum quality
pub fn setup_dac_sine(f: u32) void {
    assert(f <= 125000);
    const dma_len: u32 = blk: {
        if (f <= 7812) {
            @memcpy(dma_buffer[0..128], sine_128_data);
            break :blk 128;
        } else if (f <= 15525) {
            @memcpy(dma_buffer[0..64], sine_64_data);
            break :blk 64;
        } else if (f <= 31250) {
            @memcpy(dma_buffer[0..32], sine_32_data);
            break :blk 32;
        } else if (f <= 62500) {
            @memcpy(dma_buffer[0..16], sine_16_data);
            break :blk 16;
        } else {
            @memcpy(dma_buffer[0..8], sine_8_data);
            break :blk 8;
        }
    };

    std.log.info("Request f = {}Hz, dma_len = {}...", .{ f, dma_len });

    const samp_freq: u32 = f * dma_len;
    assert(samp_freq < 1000000);
    assert(samp_freq >= 1);

    // if samp_freq < 733, the prescaler value would not fit in the 16 bit register, thus
    // we further divide by two using the timer counter

    // Because f is minimum 1Hz, and thus samp_freq is minimum greater than 1, we
    // can simply use the prescaler in TIM6 to set the frequency (fairly coarse at higher freqs!)
    // fsample = 48_000_000 / PRESCALER thus...

    var prescaler: u32 = 48_000_000 / samp_freq;
    var divider: u32 = 1;
    while (prescaler > std.math.maxInt(u16)) {
        prescaler /= 2;
        divider *= 2;
    }

    std.log.info("prescaler = {}, divider = {}, yields f = {}Hz", .{
        prescaler,
        divider,
        48_000_000 / prescaler / dma_len,
    });
}
