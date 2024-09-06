// The signal generation logic "core" is here: Because a lot of different signals
// can be generated without "CPU intervention", we allow any of those (as long as they
// don't share pins), but only allow one "CPU-heavy" waveform out at once.

// sin may be run at any time as it's DMA + DAC (see details inside)
pub const sin = @import("signal/sin.zig");
