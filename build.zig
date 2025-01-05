const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const core = .{
        .name = "reticulum-core",
        .module = b.addModule("reticulum-core", .{
            .root_source_file = b.path("src/reticulum.zig"),
            .target = target,
            .optimize = optimize,
        }),
    };

    const test_step = b.step("test", "Run all tests.");

    // Unit tests.
    {
        const unit_tests_step = b.step("unit-tests", "Run unit tests.");
        const t = b.addTest(.{
            .name = "lib",
            .root_source_file = b.path("src/reticulum.zig"),
            .target = target,
            .optimize = optimize,
        });
        unit_tests_step.dependOn(&b.addRunArtifact(t).step);
        test_step.dependOn(unit_tests_step);
    }

    // Integration tests.
    {
        const integration_tests_step = b.step("integration-tests", "Run integration tests.");
        const integration_tests = .{
            "announce",
        };
        const imports = .{
            core,
        };

        const fixtures = b.createModule(.{
            .root_source_file = b.path("test/fixtures.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &imports,
        });

        // const ohsnap = b.dependency("ohsnap", .{});s

        inline for (integration_tests) |name| {
            const t = b.addTest(.{
                .name = name,
                .root_source_file = b.path("test/integration/" ++ name ++ ".zig"),
                .target = target,
                .optimize = optimize,
            });
            t.root_module.addImport("fixtures", fixtures);
            t.root_module.addImport(core.name, core.module);
            integration_tests_step.dependOn(&b.addRunArtifact(t).step);
        }

        test_step.dependOn(integration_tests_step);
    }
}
