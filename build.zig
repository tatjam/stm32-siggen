const std = @import("std");

const base_stm32 = "https://raw.githubusercontent.com/modm-io/cmsis-header-stm32/master/";
const base_arm = "https://raw.githubusercontent.com/ARM-software/CMSIS_6/main/";

pub fn add_cmsis_file(
    b: *std.Build,
    usf: *std.Build.Step.UpdateSourceFiles,
    comptime base_path: []const u8,
    comptime pre_path: []const u8,
    comptime name: []const u8,
) void {
    const curl_cmd = b.addSystemCommand(&[_][]const u8{"curl"});
    curl_cmd.addArg("-o");
    const curl_out = curl_cmd.addOutputFileArg(name);

    curl_cmd.addArg(base_path ++ pre_path ++ name);

    usf.step.dependOn(&curl_cmd.step);
    usf.addCopyFileToSource(curl_out, "cmsis/" ++ name);
}

pub fn download_cmsis(b: *std.Build) *std.Build.Step.UpdateSourceFiles {
    const usf = b.addUpdateSourceFiles();

    add_cmsis_file(b, usf, base_stm32, "stm32u0xx/Include/", "stm32u083xx.h");
    add_cmsis_file(b, usf, base_stm32, "stm32u0xx/Include/", "system_stm32u0xx.h");
    add_cmsis_file(b, usf, base_arm, "CMSIS/Core/Include/", "core_cm0plus.h");

    return usf;
}

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

    const firmware = b.addObjCopy(firmware_elf.*.getEmittedBin(), .{ .format = .bin });
    firmware.step.dependOn(&firmware_elf.step);

    const upload_cmd = b.addSystemCommand(&[_][]const u8{
        "echo",
        "pyocd",
        "--target",
        "target/stm32u0",
        "load",
    });
    upload_cmd.addFileArg(firmware.getOutput());
    upload_cmd.step.dependOn(&firmware.step);

    const upload = b.step("upload", "Flash connected STM32 device using system pyocd");
    upload.dependOn(&upload_cmd.step);

    const usf_cmsis = download_cmsis(b);
    const cmsis = b.step("cmsis", "Download CMSIS headers");
    cmsis.dependOn(&usf_cmsis.step);
}
