const std = @import("std");
const stm32u083 = @import("hw/stm32u083.zig");
const periph = stm32u083.devices.STM32U083.peripherals;

const volatile_loop = @import("volatile_loop.zig").volatile_loop;

const RCC = periph.RCC;
const FLASH = periph.FLASH;

pub fn setup() void {
    // NUCLEO board must be adjusted to use MCO output of STLink. This involves
    // removing SB28 and SB31 and soldering on SB27 (from the default config).
    // This puts the 8MHz signal from the STLink into PF0-OSC_IN
    // (Note that this is an external clock, not a resonator!)

    // Enable HSE in bypass mode (direct clock from STLink)
    RCC.RCC_CR.modify(.{
        .HSEBYP = @as(u1, 0x1),
        .HSEON = @as(u1, 0x1),
    });

    // We use the PLL to run the system clock as fast as possible
    // (we settle on 48MHz, becase 56MHz is outside the range of the
    // PLL, but 54 is an inconvenient number), so we must multiply HSE by 6
    // pllin can be divided by M, the VCO output may then
    // be divided by N before being fed into the phase detector
    // Finally, the VCO output may also be divided by R, Q and P
    // for the respective PLL clocks, out of which only R can be used
    // as SYSCLK
    // Now:
    // - R, Q are in [2,8]
    // - P is in [2, 32]
    // - N is in [4, 127]
    // - M is in [1, 8]
    // - VCO output must be within 96 and 344Mhz
    // - R, Q may not exceed 54MHz
    // - P may be clocked as fast as 122MHz
    // Workign backwards,
    // PLLRCLK must be at 48MHz
    // Thus frequency before R ranges from 96MHz (R = 2) to 336MHz (R = 7)
    // This frequency is precisely the VCO output
    // fVCO = 48 * R
    // Which we can achieve by dividing the VCO output, before phase
    // detection, by  N = 48 * R / 8 = 6 * R, which is a valid value for all R.
    // (We choose R = 2)

    RCC.RCC_PLLCFGR.modify(.{
        .PLLSRC = @as(u2, 0b11), // PLLSRC = HSE
        .PLLN = @as(u7, 12), // HSE * 12 = 96MHz is output by VCO
        .PLLR = @as(u3, 0b001), // VCO output is divided by 2 for SYSCLK (48MHz)
    });

    // Launch PLL
    RCC.RCC_CR.modify(.{
        .PLLON = @as(u1, 0x1),
    });

    // Wait for PLL lock
    while (RCC.RCC_CR.read().PLLRDY.raw != 0x1) {
        volatile_loop();
    }

    // Enable R output
    RCC.RCC_PLLCFGR.modify(.{
        .PLLREN = @as(u1, 0x1),
    });

    // Before changing SYSCLK, change FLASH latency
    // For 48MHz on Vcore range 1 (default) we use 1 wait state
    FLASH.FLASH_ACR.modify(.{
        .LATENCY = @as(u3, 0b001),
    });

    // Wait for bit to set, which indicates change successful
    while (FLASH.FLASH_ACR.read().LATENCY.raw & 0b001 == 0) {
        volatile_loop();
    }

    // Use PLL R output as SYSCLK
    RCC.RCC_CFGR.modify(.{
        .SW = @as(u3, 0b011),
    });

    // SYSCLK is thus at 48MHz
}
