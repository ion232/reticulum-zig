const std = @import("std");

const Target = std.Build.ResolvedTarget;
const Optimize = std.builtin.OptimizeMode;

pub fn build(b: *std.Build) void {
    var builder = Builder.init(b);
    builder.examples();
    builder.tests();
}

const Builder = struct {
    const Self = @This();

    const Package = enum { app, core, io };
    const TestSuite = enum { integration, simulation };

    b: *std.Build,
    target: Target,
    optimize: Optimize,

    pub fn init(b: *std.Build) Self {
        const target = b.standardTargetOptions(.{});
        const optimize = b.standardOptimizeOption(.{});
        const core = b.addModule(@tagName(.core), .{
            .root_source_file = b.path(@tagName(.core) ++ "/lib.zig"),
            .target = target,
            .optimize = optimize,
        });
        const io = b.addModule(@tagName(.io), .{
            .root_source_file = b.path(@tagName(.io) ++ "/lib.zig"),
            .target = target,
            .optimize = optimize,
        });

        io.addImport(@tagName(.core), core);

        return .{
            .b = b,
            .target = target,
            .optimize = optimize,
        };
    }

    pub fn examples(self: *Self) void {
        const step = self.b.step("example", "Run an example");

        const name = self.b.option([]const u8, "name", "The module name to run") orelse return;
        const example = self.b.addExecutable(.{
            .name = self.b.fmt("example-{s}", .{name}),
            .root_source_file = self.b.path(self.b.fmt("examples/{s}.zig", .{name})),
            .target = self.target,
            .optimize = self.optimize,
        });

        self.addImport(example, .core);
        self.addImport(example, .io);

        const run = self.b.addRunArtifact(example);
        run.step.dependOn(self.b.getInstallStep());

        if (self.b.args) |args| {
            run.addArgs(args);
        }

        step.dependOn(&run.step);
    }

    pub fn tests(self: *Self) void {
        const test_step = self.b.step("test", "Run all tests");

        const unit_tests = self.unitTests();
        const integration_tests = self.testSuite(.integration);
        const simulation_tests = self.testSuite(.simulation);

        test_step.dependOn(unit_tests);
        test_step.dependOn(integration_tests);
        test_step.dependOn(simulation_tests);
    }

    fn unitTests(self: *Self) *std.Build.Step {
        const step = self.b.step("unit-tests", "Run unit tests");

        inline for (.{ .app, .core, .io }) |t| {
            const root = if (t == .app) "main" else "lib";
            const compile = self.b.addTest(.{
                .name = @tagName(t),
                .root_source_file = self.b.path(@tagName(t) ++ "/" ++ root ++ ".zig"),
                .target = self.target,
                .optimize = self.optimize,
            });
            step.dependOn(&self.b.addRunArtifact(compile).step);
        }

        return step;
    }

    fn testSuite(self: *Self, comptime suite: TestSuite) *std.Build.Step {
        const category = @tagName(suite);
        const root_directory = "test/" ++ category;
        const step = self.b.step(category ++ "-tests", "Run " ++ category ++ " tests");

        const test_names = switch (suite) {
            .integration => .{"tcp"},
            .simulation => .{ "announce", "plain" },
        };

        const packages = switch (suite) {
            .integration => .{ .core, .io },
            .simulation => .{.core},
        };

        const ohsnap = blk: {
            const module_names: []const []const u8 = &[_][]const u8{"root"} ** test_names.len;
            const root_directories: []const []const u8 = &[_][]const u8{root_directory} ** test_names.len;

            break :blk self.b.dependency("ohsnap", .{
                .target = self.target,
                .optimize = self.optimize,
                .module_name = module_names,
                .root_directory = root_directories,
            });
        };

        inline for (test_names) |name| {
            const t = self.b.addTest(.{
                .name = name,
                .root_source_file = self.b.path(root_directory ++ "/" ++ name ++ ".zig"),
                .target = self.target,
                .optimize = self.optimize,
            });

            inline for (packages) |package| {
                self.addImport(t, package);
            }

            t.root_module.addImport("golden", ohsnap.module("ohsnap"));
            step.dependOn(&self.b.addRunArtifact(t).step);
        }

        return step;
    }

    fn addImport(self: *Self, compile: *std.Build.Step.Compile, comptime package: Package) void {
        compile.root_module.addImport(@tagName(package), self.b.modules.getPtr(@tagName(package)).?.*);
    }
};
