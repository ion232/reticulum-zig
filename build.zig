const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Core module.
    const core = .{
        .name = "reticulum",
        .module = b.addModule("reticulum-core", .{
            .root_source_file = b.path("core/reticulum.zig"),
            .target = target,
            .optimize = optimize,
        }),
    };

    // All tests.
    const test_step = b.step("test", "Run all tests.");

    // Unit tests.
    {
        const unit_tests_step = b.step("unit-tests", "Run unit tests.");
        test_step.dependOn(unit_tests_step);

        const t_app = b.addTest(.{
            .name = "app",
            .root_source_file = b.path("app/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_tests_step.dependOn(&b.addRunArtifact(t_app).step);

        const t_core = b.addTest(.{
            .name = "core",
            .root_source_file = b.path("core/reticulum.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_tests_step.dependOn(&b.addRunArtifact(t_core).step);
    }

    // Deterministic simulation tests.
    {
        const simulation_tests_step = b.step("simulation-tests", "Run simulation tests.");
        test_step.dependOn(simulation_tests_step);

        const ohsnap = blk: {
            // Root directories map to module names.
            const name = "root";
            const root = "test/simulation";

            const module_names: []const []const u8 = &.{
                name,
                name,
            };
            const root_directory: []const []const u8 = &.{
                root,
                root,
            };

            break :blk b.dependency("ohsnap", .{
                .target = target,
                .optimize = optimize,
                .module_name = module_names,
                .root_directory = root_directory,
            });
        };

        const simulation_tests = .{
            "announce",
            "plain",
        };

        inline for (simulation_tests) |name| {
            const t = b.addTest(.{
                .name = name,
                .root_source_file = b.path("test/simulation/" ++ name ++ ".zig"),
                .target = target,
                .optimize = optimize,
            });
            t.root_module.addImport(core.name, core.module);
            t.root_module.addImport("golden", ohsnap.module("ohsnap"));
            simulation_tests_step.dependOn(&b.addRunArtifact(t).step);
        }
    }
}
