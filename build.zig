const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tests = b.addTest(.{
        .root_source_file = b.path("src/Test.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests.");
    test_step.dependOn(&run_tests.step);

    // const exe = b.addExecutable(.{
    //     .name = "exe",
    //     .root_source_file = b.path("src"),
    //     .target = target,
    //     .optimize = optimize,
    // });
    // const run_exe = b.addRunArtifact(exe);
    // const exe_step = b.step("exe", "Run executable.");
    // exe_step.dependOn(&run_exe.step);
}
