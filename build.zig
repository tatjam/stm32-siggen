const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .thumb,
        .os_tag = .freestanding,
        .abi = .eabi, // We don't have hardware float
        .cpu_model = std.Target.Query.CpuModel{
            .explicit = &std.Target.arm.cpu.cortex_m0plus,
        },
    });

    const optimize = b.standardOptimizeOption(.{});

    const firmware_elf = b.addExecutable(.{
        .name = "firmware.elf",
        .target = target,
        .optimize = optimize,
        .link_libc = false,
        .linkage = .static,
        .single_threaded = true,
        .root_source_file = b.path("src/main.zig"),
    });
    firmware_elf.setLinkerScript(b.path("link/stm32u083rc.ld"));

    // For debugging it's better to use the elf file
    b.installArtifact(firmware_elf);

    const upload_cmd = b.addSystemCommand(&[_][]const u8{
        "pyocd",
        "load",
        "--target",
        "stm32u083rctx",
        "--format",
        "elf",
    });
    upload_cmd.addFileArg(firmware_elf.getEmittedBin());
    upload_cmd.step.dependOn(&firmware_elf.step);

    const upload = b.step("upload", "Flash connected STM32 device using system pyocd");
    upload.dependOn(&upload_cmd.step);
}
