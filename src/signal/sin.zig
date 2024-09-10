// Sine wave (fairly coarse frequency, prioritizes harmonic purity) generation using DAC
// NOTE: DMA1 channel 0 (index 1 in register names) is reserved for this purpose
// NOTE: DMAMUX channel 0 is thus also reserved for this purpose
// NOTE: TIM6 is reserved for this purpose
// NOTE: Pin PA4 is reserved for this purpose
const std = @import("std");
const assert = std.debug.assert;

const stm32u083 = @import("../hw/stm32u083.zig").devices.STM32U083;
const DMA = stm32u083.peripherals.DMA1;
const DMAMUX = stm32u083.peripherals.DMAMUX;
const TIM = stm32u083.peripherals.TIM6;
const DAC = stm32u083.peripherals.DAC;
const GPIO = stm32u083.peripherals.GPIOA;
const RCC = stm32u083.peripherals.RCC;

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
    var out: [n]comptime_float = undefined;

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
    var out: [n]u16 = undefined;
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
    return convert_data_to_dac_format(n, generate_sine_data_f64(n));
}

// This is all generated at comptime
pub const sine_8_data: [8]u16 = generate_sine_data(8);
pub const sine_16_data: [16]u16 = generate_sine_data(16);
pub const sine_32_data: [32]u16 = generate_sine_data(32);
pub const sine_64_data: [64]u16 = generate_sine_data(64);
pub const sine_128_data: [128]u16 = generate_sine_data(128);

var dma_buffer: [128]u16 = undefined;

// Launches a sine generator given frequency in hertz that
// best approximates this frequency on the output with
// maximum quality
pub fn start(f: u32) !void {
    assert(stm32u083.peripherals.RCC.RCC_IOPENR.read().GPIOAEN.raw == 1);

    if (f > 125000 or f == 0) return error.InvalidFrequency;
    const dma_len: u32 = blk: {
        if (f <= 7812) {
            @memcpy(dma_buffer[0..128], &sine_128_data);
            break :blk 128;
        } else if (f <= 15525) {
            @memcpy(dma_buffer[0..64], &sine_64_data);
            break :blk 64;
        } else if (f <= 31250) {
            @memcpy(dma_buffer[0..32], &sine_32_data);
            break :blk 32;
        } else if (f <= 62500) {
            @memcpy(dma_buffer[0..16], &sine_16_data);
            break :blk 16;
        } else {
            @memcpy(dma_buffer[0..8], &sine_8_data);
            break :blk 8;
        }
    };

    const samp_freq: u32 = f * dma_len;
    assert(samp_freq < 1000000);
    assert(samp_freq >= 1);

    // if samp_freq < 733, the prescaler value would not fit in the 16 bit register, thus
    // we further divide by two using the timer counter

    // Because f is minimum 1Hz, and thus samp_freq is minimum greater than 1, we
    // can simply use the prescaler in TIM6 to set the frequency (fairly coarse at higher freqs!)
    // fsample = 48_000_000 / PRESCALER thus...

    // division by two because divider is minimum 2;
    var prescaler: u32 = 48_000_000 / samp_freq / 2;
    var divider: u32 = 2;
    while (prescaler > std.math.maxInt(u16)) {
        prescaler /= 2;
        divider *= 2;
    }

    assert(prescaler <= std.math.maxInt(u16));
    assert(divider <= std.math.maxInt(u16));
    assert(prescaler > 0);
    assert(divider >= 2);

    // Not sure if the other arrangement is better? Should not matter much...
    TIM.TIM6_PSC.write_raw(@as(u16, @truncate(prescaler - 1)));
    // NOTE: The timer counts from 0 to TIM6_ARR, and then restarts. The value may not be 0!
    // Otherwise, no update events are generated. This means that we divide minimum by 2.
    TIM.TIM6_ARR.write_raw(@as(u16, @truncate(divider - 1)));

    // Make sure we generate an update to load registers (?)
    TIM.TIM6_EGR.modify(.{
        .UG = @as(u1, 1),
    });

    std.log.info("Request f = {}Hz, dma_len = {}...", .{ f, dma_len });
    std.log.info("prescaler = {}, divider = {}, yields f = {}Hz", .{
        prescaler,
        divider,
        48_000_000 / prescaler / divider / dma_len,
    });

    // The DAC upon external triggering will request a new sample from DMA, which will be
    // output on next trigger. We use TIM6 to do the triggering, and thus
    // the "driving order" is TIM6 -> DAC -> DMA

    // Write first sample as 0 to prevent garbage output
    // (First output is not served by DMA!)
    DAC.DAC_DHR12R1.modify(.{
        .DACC1DHR = @as(u12, 2048),
    });

    // Set GPIOA PA4 pin to analog function mode
    // NOTE: This is default
    GPIO.GPIOA_MODER.modify(.{
        .MODE4 = @as(u2, 0b11), // Analog mode
    });

    // Route DAC DMA requests to DMA1 channel 0
    // We thus use DMAMUX channel 0 (index 1)
    // (There is a 1-to-1 mapping of DMAMUX channels and DMA channels!)
    DMAMUX.DMAMUX_C0CR.modify(.{
        .DMAREQ_ID = @as(u7, 8), // DMA request 8 is hardwired to the DAC
    });

    // Set up the generator to map

    // Setup DMA
    DMA.DMA_CCR1.modify(.{
        .MSIZE = @as(u2, 0b01), // Samples are 16 bit
        .PSIZE = @as(u2, 0b01), // Target is 16 bit TODO: CHECK
        .MINC = @as(u1, 1), // We increase memory
        .CIRC = @as(u1, 1), // Circular mode
        .DIR = @as(u1, 1), // Read from memory
    });

    DMA.DMA_CMAR1.modify(.{
        .MA = @intFromPtr(&dma_buffer[0]),
    });

    DMA.DMA_CPAR1.modify(.{
        .PA = @intFromPtr(&DAC.DAC_DHR12R1.raw),
    });

    std.log.info("{}, {}", .{ &dma_buffer[0], &DAC.DAC_DHR12R1.raw });

    DMA.DMA_CNDTR1.modify(.{
        .NDT = @as(u16, @truncate(dma_len)),
    });

    // Make DAC use DMA, trigger from TIM6, and enable it
    DAC.DAC_CR.modify(.{
        .DMAEN1 = @as(u1, 1),
        .TEN1 = @as(u1, 1), // use hardware trigger
        .TSEL1 = @as(u4, 5), // dac_ch1_trg5 = tim6_trgo
        .WAVE1 = @as(u2, 0b00),
        .EN1 = @as(u1, 1),
    });

    // Launch DMA
    DMA.DMA_CCR1.modify(.{
        .EN = @as(u1, 1),
    });

    // Make sure timer starts at 0
    TIM.TIM6_CNT.modify(.{
        .CNT = @as(u16, 0),
    });

    // And make sure it uses its update event as TRGO (which goes to DAC)
    TIM.TIM6_CR2.modify(.{
        .MMS = @as(u3, 0b010),
    });

    // Launch timer, this starts the continuous generation
    TIM.TIM6_CR1.modify(.{
        .CEN = @as(u1, 1),
    });
}

pub fn stop() void {
    // If we stop TIM6, everything that's driven stops
    TIM.TIM6_CR1.modify(.{
        .CEN = @as(u1, 0),
    });

    // Disable also DMA so we can change values
    DMA.DMA_CCR1.modify(.{
        .EN = @as(u1, 0),
    });

    // DAC can stay enabled, it should be fine
}
