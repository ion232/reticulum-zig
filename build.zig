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

    // Integration tests.
    {
        const integration_tests_step = b.step("integration-tests", "Run integration tests.");
        test_step.dependOn(integration_tests_step);

        const integration_tests = .{
            "announce",
        };

        const ohsnap = b.dependency("ohsnap", .{});

        inline for (integration_tests) |name| {
            const t = b.addTest(.{
                .name = name,
                .root_source_file = b.path("test/integration/" ++ name ++ ".zig"),
                .target = target,
                .optimize = optimize,
            });
            t.root_module.addImport(core.name, core.module);
            t.root_module.addImport("ohsnap", ohsnap.module("ohsnap"));
            integration_tests_step.dependOn(&b.addRunArtifact(t).step);
        }
    }
}
