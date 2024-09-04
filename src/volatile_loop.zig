// TODO: This function is uneeded once Zig issue #21033 is fixed
// But it may be convenient to leave for "semantic intent" (make it really
// clear that the loop expects an external event to change its predicate)
pub fn volatile_loop() void {
    asm volatile ("" ::: "memory");
}
