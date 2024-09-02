// The signal generation logic "core" is here: Because a lot of different signals
// can be generated without "CPU intervention", we allow any of those (as long as they
// don't share pins), but only allow one "CPU-heavy" waveform out at once.
