// This file implements the connection to the computer (through the STLink)
// In the future this could be expanded to use tinyusb or similar, although the
// NUCLEO board doesn't have a USB port connected to the MCU!
// Of course, using the STLink as a serial device is not optimal, but we don't
// move big ammounts of data anyway...

// By default on the NUCLEO board USART2 (PA2/PA3) is used as VCP (Virtual COM port),
// so we use it just for this purpose :)

// This is not a great serial driver! DMA and other advanced features could be
// used instead of raw byte writing, but this is easier and we don't need high
// throughput in the program.

const stm32u083 = @import("../hw/stm32u083.zig");
const periph = stm32u083.devices.STM32U083.peripherals;

const std = @import("std");

const RCC = periph.RCC;
const USART = periph.USART2;

pub fn init_serial() void {
    // We setup Asynchronous mode, baud rate of
    // 9600bps, 8 bits word length with parity = None,
    // 1 stop bit, 16 oversampling
    // PA2/PA3 are used so enable GPIOA
    periph.RCC.RCC_IOPENR.modify(.{
        .GPIOAEN = @as(u1, 0b01), // Enable
    });

    periph.GPIOA.GPIOA_MODER.modify(.{
        .MODE2 = @as(u2, 0b10), // Special purpose mode
        .MODE3 = @as(u2, 0b10), // Special purpose mode
    });

    // USART is alternate function 7 (datasheet, not manual!)
    periph.GPIOA.GPIOA_AFRL.modify(.{
        .AFSEL2 = @as(u4, 7),
        .AFSEL3 = @as(u4, 7),
    });

    // To achieve 9600bps, from our 46MHz clock, we use USARTDIV
    // and divide the input clock by 8 (to 5750kHz)
    // (See 33.5.8 of the STM32 manual)
    //  USART_DIV = UART_KER_CLK / BAUD
    //            = 5750 / 9.6 = 598.96
    // We round to 599 (which yields baudrate of 9599bps, close enough)

    // Enable clocking. We clock the UART from SYSCLK
    // so that we have 46MHz on its input
    RCC.RCC_CCIPR.modify(.{
        .USART2SEL = @as(u2, 0b01),
    });
    // Enable UART clock so we can change registers
    RCC.RCC_APBENR1.modify(.{
        .USART2EN = @as(u1, 1),
    });

    USART.USART_PRESC.write_raw(@as(u4, 0b0100)); // Divide by 8

    // Setup USART_BRR for 9(599)bps
    USART.USART_BRR.write_raw(@as(u16, 599));

    // Enable transmission and reception
    USART.USART_CR1.modify(.{
        .UE = @as(u1, 1),
        .TE = @as(u1, 1),
    });

    std.log.info("Hello from NUCLEO!", .{});
}

pub fn write_byte(byte: u8) void {
    // Wait for write to be ready
    // NOTE: This is actually a read of TXE
    while (USART.USART_ISR.read().TXFNF.raw == 0) {}
    // Actually write the data
    USART.USART_TDR.modify(.{
        .TDR = @as(u9, byte),
    });
}

pub const serial_log_indicator = 0x02; // STX

var serial_log_buffer: [128]u8 = undefined;

pub fn serial_log(
    comptime message_level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const level_txt = comptime message_level.asText();
    const prefix2 = if (scope == .default) ": " else "(" ++ @tagName(scope) ++ "): ";
    const printed = std.fmt.bufPrint(&serial_log_buffer, format, args) catch blk: {
        break :blk "(fmt msg error)";
    };
    // Message indicator
    write_byte(serial_log_indicator);
    // The prefix followed by the message
    for (level_txt) |b| {
        write_byte(b);
    }
    for (prefix2) |b| {
        write_byte(b);
    }
    for (printed) |b| {
        write_byte(b);
    }
    // Message end indicator
    write_byte('\n');
    write_byte('\r');
    write_byte(0x0);
}

pub fn interrupt_handler() callconv(.C) void {}
