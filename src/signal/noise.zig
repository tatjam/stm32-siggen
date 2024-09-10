// Noise generator using the dedicated DAC mode
// NOTE: DMA1 channel 0 (index 1 in register names) is reserved for this purpose
// NOTE: TIM6 is reserved for this purpose
// NOTE: Pin PA4 is reserved for this purpose

const stm32u083 = @import("../hw/stm32u083.zig").devices.STM32U083;
const TIM = stm32u083.peripherals.TIM6;
const DAC = stm32u083.peripherals.DAC;
const GPIO = stm32u083.peripherals.GPIOA;
const RCC = stm32u083.peripherals.RCC;

pub fn start(rate: u32) !void {
    DAC.DAC_DHR12R1.modify(.{
        .DACC1DHR = @as(u12, 2048),
    });

    // Set GPIOA PA4 pin to analog function mode
    // NOTE: This is default
    GPIO.GPIOA_MODER.modify(.{
        .MODE4 = @as(u2, 0b11), // Analog mode
    });

    // Make DAC not use DMA, trigger from TIM6, and enable it
    // We also enable noise generation
    DAC.DAC_CR.modify(.{
        .DMAEN1 = @as(u1, 0),
        .TEN1 = @as(u1, 1), // use hardware trigger
        .TSEL1 = @as(u4, 5), // dac_ch1_trg5 = tim6_trgo
        .WAVE1 = @as(u2, 0b01),
        .MAMP1 = @as(u4, 0b1011), // maximum amplitude?
        .EN1 = @as(u1, 1),
    });

    // Make sure timer starts at 0
    TIM.TIM6_CNT.modify(.{
        .CNT = @as(u16, 0),
    });

    // Make timer generate 1Msps for widest bandwidth possible
    // Remember than TIM6 is clocked at 48MHz, thus to get 1Msps
    // we divide by minimum 48
    if (rate < 48) {
        return error.InvalidNoiseRate;
    }
    TIM.TIM6_PSC.write_raw(@as(u16, @truncate(rate)));
    TIM.TIM6_ARR.write_raw(@as(u16, 1));

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
}
