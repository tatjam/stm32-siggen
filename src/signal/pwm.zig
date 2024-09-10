// General square wave generation using timers. We allow 2 different frequencies
// each of which can have up to 2 channels
// NOTE: TIM2 and TIM3 are reserved for this purpose
// NOTE: Pins PA0, PB10, PB4, PB0 are reserved for this purpose
// NOTE: These correspond to NUCLEO's A0, PWM/D6, PWM/D5, A3 respectively
//
// To achieve maximum duty cycle / phase precision, we divide the clock as little as
// possible, but in such a way that the frequency is achievable within the 16 bit
// counter (we don't exploit the 32 bit counter for code brevity)

const std = @import("std");
const assert = std.debug.assert;

const stm32u083 = @import("../hw/stm32u083.zig").devices.STM32U083;
const GPIO = stm32u083.peripherals.GPIOA;
const RCC = stm32u083.peripherals.RCC;

/// Freq set to 0 disables the whole timer block
/// duty set to 0 disables a timer channel
/// Each TimerSettings represents up to two PWM signals at the same frequency!
/// freq is given in Hz
/// The timer will count up and down every 1.0 / freq, thus
/// each upcount and downcount happens every 2.0 / freq (or at 0.5 freq)
/// start determines at what percent of the upcount the output goes high/low
/// end determines at what percent of the downcount the output goes low/high
/// whether high/low is selected depends on mode, allowing phase inversion
/// if start = 100 and end = 0 for a channel, it's disabled
pub const TimerSettings = struct {
    freq: u32,
    start0: u8,
    start1: u8,
    end0: u8,
    end1: u8,
    mode0: bool,
    mode1: bool,
};

fn disabled() TimerSettings {
    return TimerSettings{
        .freq = 0,
        .start0 = 100,
        .end0 = 0,
        .start1 = 100,
        .end1 = 0,
        .mode0 = false,
        .mode1 = false,
    };
}

pub fn all_disabled() [2]TimerSettings {
    var out: [2]TimerSettings = undefined;
    out[0] = disabled();
    out[1] = disabled();
    return out;
}

fn calc_divider_and_counter(freq: u32) struct { presc: u16, cnt: u16 } {
    // 16 bit counter allows us to go from 24MHz = 48MHz / 2 (counter = 1)
    // down to 366
    assert(freq > 0);

    var presc: u32 = 0;
    var cnt: u32 = 24_000_000 / freq;
    while (cnt > std.math.maxInt(u16)) {
        presc += 1;
        cnt = 24_000_000 / (presc + 1) / freq;
    }

    assert(presc <= std.math.maxInt(u16));
    assert(cnt <= std.math.maxInt(u16));

    const acc = 24_000_000 / (presc + 1);

    std.log.info("presc = {}, cnt = {} yield freq = {}Hz with accuracy = {}Hz ({}%)", .{
        presc,
        cnt,
        24_000_000 / (presc + 1) / cnt,
        acc,
        100 * acc / 24_000_000 / (presc + 1) / cnt,
    });

    return .{ .presc = @intCast(presc), .cnt = @intCast(cnt) };
}

fn start_timer_tim2(settings: TimerSettings) !void {
    const TIM = stm32u083.peripherals.TIM2;
    const pre = calc_divider_and_counter(settings.freq);
    // Set frequency
    TIM.TIM2_PSC.write_raw(pre.presc);
    TIM.TIM2_ARR.write_raw(@intCast(pre.cnt));
    // Set assymetric PWM mode

    // We start with setting up / down counting
    TIM.TIM2_CR1.modify(.{
        .CMS = @as(u2, 0b11),
    });

    // We use OC1 and OC3 on both timers
    // (We manually write because this is an alternate register)
    if (settings.mode0) {
        TIM.TIM2_CCMR1.raw |= 0b0000000_0_0000000_1_0_000_0_0_00_0_111_0_0_00;
    } else {
        TIM.TIM2_CCMR1.raw &= ~@as(u32, 0b0000000_0_0000000_0_0_000_0_0_00_0_001_0_0_00);
        TIM.TIM2_CCMR1.raw |= 0b0000000_0_0000000_1_0_000_0_0_00_0_110_0_0_00;
    }
    if (settings.mode1) {
        TIM.TIM2_CCMR2.raw |= 0b0000000_0_0000000_1_0_000_0_0_00_0_111_0_0_00;
    } else {
        TIM.TIM2_CCMR2.raw &= ~@as(u32, 0b0000000_0_0000000_0_0_000_0_0_00_0_001_0_0_00);
        TIM.TIM2_CCMR2.raw |= 0b0000000_0_0000000_1_0_000_0_0_00_0_110_0_0_00;
    }
    // Set triggers for start / stop, converting from percent
    const start0u32: u32 = @intCast(settings.start0);
    const start1u32: u32 = @intCast(settings.start1);
    const end0u32: u32 = @intCast(settings.end0);
    const end1u32: u32 = @intCast(settings.end1);
    const start0 = (start0u32 * pre.cnt) / 100;
    const start1 = (start1u32 * pre.cnt) / 100;
    const end0 = (end0u32 * pre.cnt) / 100;
    const end1 = (end1u32 * pre.cnt) / 100;
    std.log.info("start0 = {} end0 = {} start1 = {} end1 = {}", .{ settings.start0, settings.end0, settings.start1, settings.end1 });
    std.log.info("start0 = {} end0 = {} start1 = {} end1 = {}", .{ start0, end0, start1, end1 });
    TIM.TIM2_CCR1.raw = @as(u16, @truncate(start0));
    TIM.TIM2_CCR2.raw = @as(u16, @truncate(end0));
    TIM.TIM2_CCR3.raw = @as(u16, @truncate(start1));
    TIM.TIM2_CCR4.raw = @as(u16, @truncate(end1));

    // Start from 0
    TIM.TIM2_CNT.write_raw(0);

    // Use channels as outputs
    TIM.TIM2_CCER.modify(.{
        .CC1E = @as(u1, 1),
        .CC3E = @as(u1, 1),
    });

    // Enable the channels
    if (!(settings.start0 == 100 and settings.end0 == 0)) {
        TIM.TIM2_CCMR1.raw |= 0b0000000_0_0000000_0_0_000_0_0_00_1_000_0_0_00;
    } else {
        TIM.TIM2_CCMR1.raw &= ~@as(u32, 0b0000000_0_0000000_0_0_000_0_0_00_1_000_0_0_00);
    }
    if (!(settings.start1 == 100 and settings.end1 == 0)) {
        TIM.TIM2_CCMR2.raw |= 0b0000000_0_0000000_0_0_000_0_0_00_1_000_0_0_00;
    } else {
        TIM.TIM2_CCMR1.raw &= ~@as(u32, 0b0000000_0_0000000_0_0_000_0_0_00_1_000_0_0_00);
    }

    // Launch the timer
    TIM.TIM2_CR1.modify(.{
        .CEN = @as(u1, 1),
    });
}

fn start_timer_tim3(settings: TimerSettings) !void {
    _ = settings; // autofix

}

// Set any frequency to 0 to disable said timer, and set any phase to 0 to dis
pub fn start(settings: [2]TimerSettings) !void {
    if (settings[0].freq != 0) {
        try start_timer_tim2(settings[0]);
    }
    if (settings[1].freq != 0) {
        try start_timer_tim3(settings[1]);
    }
}

pub fn build_settings(freq: u32, phase: u8, duty: u8) TimerSettings {
    const out: TimerSettings = undefined;
    _ = freq; // autofix
    _ = phase; // autofix
    _ = duty; // autofix

    return out;
}

pub fn stop() void {
    stm32u083.peripherals.TIM2.TIM2_CR1.modify(.{
        .CEN = @as(u1, 0),
    });
    stm32u083.peripherals.TIM3.TIM3_CR1.modify(.{
        .CEN = @as(u1, 0),
    });
    stm32u083.peripherals.TIM2.TIM2_CCER.modify(.{
        .CC1E = @as(u1, 0),
        .CC3E = @as(u1, 0),
    });
}
