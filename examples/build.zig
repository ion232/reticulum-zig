const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const reticulum = b.dependency("reticulum", .{
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "mvp",
        .root_source_file = b.path("mvp/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("reticulum", reticulum.module("reticulum"));
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    const run_step = b.step("mvp", "Run the mvp code.");
    run_step.dependOn(&run_cmd.step);
}
