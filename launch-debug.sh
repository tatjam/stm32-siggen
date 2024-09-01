pyocd gdbserver &
gdb-multiarch zig-out/bin/firmware.elf -ex "target remote 0.0.0.0:3333"
