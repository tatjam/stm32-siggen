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

const stm32u083 = @import("hw/stm32u083.zig").devices.STM32U083;
const periph = stm32u083.peripherals;
const volatile_loop = @import("volatile_loop.zig").volatile_loop;
const std = @import("std");

const signal = @import("signal.zig");

const RCC = periph.RCC;
const USART = periph.USART2;

const ACK = 0x06;
const NACK = 0x15;

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

    // Enable transmission and reception, and interrupts
    USART.USART_CR1.modify(.{
        .UE = @as(u1, 1),
        .TE = @as(u1, 1),
        .RE = @as(u1, 1),
        .RXFNEIE = @as(u1, 1), // This is actually RXNEIE, but alternate 0 is used
    });

    stm32u083.enable_interrupt(.USART2_LPUART2);

    std.log.info("Hello from NUCLEO!", .{});
}

pub fn write_byte(byte: u8) void {
    // Wait for write to be ready
    // NOTE: This is actually a read of TXE
    while (USART.USART_ISR.read().TXFNF.raw == 0) {
        volatile_loop();
    }
    // Actually write the data
    USART.USART_TDR.modify(.{
        .TDR = @as(u9, byte),
    });
}

pub const serial_log_indicator = 0x02; // STX

var serial_log_buffer: [128]u8 = undefined;

// We use a double buffered input buffer
var proc_command_buffer: [32]u8 = undefined;
var proc_buffer_size: u32 = 0;
var command_buffer: [32]u8 = undefined;
var command_ptr: u32 = 0;
var command_overflow: u32 = 0;
var has_buffer: bool = false;

fn newline() void {
    write_byte('\r');
    write_byte('\n');
}

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
    newline();
}

pub fn interrupt_handler() callconv(.C) void {
    if (USART.USART_ISR.read().RXFNE.raw == 1) {
        // This is actually RXNE (we use variant 0)
        // Reading RDR will clear this interrupt flag!

        const byte_parity = USART.USART_RDR.read().RDR;
        // We have parity disabled, so the MSB should always be zero and this is fine
        const byte = @as(u8, @truncate(byte_parity));
        if (byte == 0x08) {
            // Backspace, which for wathever reason is not in Zig
            if (command_ptr > 0) {
                command_ptr -= 1;
            }
        } else {
            command_buffer[command_ptr] = byte;
            command_ptr += 1;
            // Note that the 0 terminator IS included in the message
            if (byte == '\n' or byte == '\r' or command_ptr >= command_buffer.len) {
                if (has_buffer) {
                    // Sadly messages came too fast, discard last received but notify
                    // (This prevents data races from corrupting a message as it's being read in the task!)
                    command_overflow += 1;
                    command_ptr = 0;
                } else {
                    // End of command, queue buffer to be processed
                    @memcpy(proc_command_buffer[0..command_ptr], command_buffer[0..command_ptr]);
                    proc_buffer_size = command_ptr;
                    command_ptr = 0;
                    has_buffer = true;
                }
            }
        }
    } else {
        unreachable;
    }
}

var was_parsing_raw_data = false;

// All commands are of the form [noun] [values...] so we can decompose them
fn task_command(buffer: []u8) !void {
    var tokens = std.mem.tokenizeAny(u8, buffer, " \r\n");
    const cmd = tokens.next() orelse return error.InvalidSerial;
    if (std.mem.eql(u8, cmd, "sine")) {
        const arg1 = tokens.next() orelse return error.LackArguments;
        if (std.mem.eql(u8, arg1, "dis")) {
            signal.sin.stop();
        } else {
            const as_number = try std.fmt.parseInt(u32, arg1, 0);
            signal.sin.stop();
            try signal.sin.start(as_number);
        }
    } else {
        return error.UnknownCommand;
    }
}

pub fn task_receive() void {
    if (has_buffer) {
        const buffer = proc_command_buffer[0..proc_buffer_size];
        // Process the buffer
        if (was_parsing_raw_data) {
            // TODO
        } else {
            // Newline for comfortable terminal use
            newline();
            if (task_command(buffer)) {
                write_byte(ACK);
                newline();
            } else |err| {
                std.log.err("Invalid command, error: {s}", .{@errorName(err)});
                write_byte(NACK);
            }
        }

        has_buffer = false;
    }
}
