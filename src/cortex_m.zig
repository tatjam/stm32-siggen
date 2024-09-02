const NVIC_Type = extern struct {
    ISER: u32,
    reserved_0: [31]u32,
    ICER: u32,
    reserved_1: [31]u32,
    ISPR: u32,
    reserved_2: [31]u32,
    ICPR: u32,
    reserved_3: [31]u32,
    reserved_4: [64]u32,
    IP: [8]u32,
};

const SysTick_Type = extern struct {
    CTRL: u32,
    LOAD: u32,
    VAL: u32,
    CALIB: u32,
};

const SCB_Type = extern struct {
    CPUID: u32,
    ICSR: u32,
    reserved_0: u32,
    AIRCR: u32,
    SCR: u32,
    CCR: u32,
    reserved_1: u32,
    SHP: u32[2],
    SHCSR: u32,
};

pub const NVIC: *volatile NVIC_Type = @ptrFromInt(0xE000E000 + 0x0100);
pub const SysTick: *volatile SysTick_Type = @ptrFromInt(0xE000E000 + 0x0010);
pub const SCB: *volatile SCB_Type = @ptrFromInt(0xE000E000 + 0x0D00);

const InterruptIndex = @import("stm32u083.zig").devices.STM32U083.InterruptIndex;

const InterruptSave = struct {
    ISER: u32,
    SysTick: bool,
};

// Obviously doesn't disable NMI
pub fn disable_interrupts() InterruptSave {
    var out: InterruptSave = undefined;

    out.ISER = NVIC.ISER;
    out.SysTick = SysTick.CTRL & 0b10;

    return out;
}

pub fn restore_interrupts(s: InterruptSave) void {
    NVIC.ISER = s.ISER;
    if (s.SysTick) {
        SysTick.CTRL = SysTick.CTRL | 0b10;
    }
}
