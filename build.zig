const std = @import("std");

const Target = std.Build.ResolvedTarget;
const Optimize = std.builtin.OptimizeMode;

pub fn build(b: *std.Build) void {
    var builder = Builder.init(b);
    builder.c();
    builder.examples();
    builder.tests();
    builder.wasm();
}

const Builder = struct {
    const Self = @This();

    const Package = enum { app, core, io };
    const TestSuite = enum { integration, simulation };

    b: *std.Build,
    options: *std.Build.Step.Options,
    target: Target,
    optimize: Optimize,

    pub fn init(b: *std.Build) Self {
        const options = b.addOptions();
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
            .options = options,
            .target = target,
            .optimize = optimize,
        };
    }

    pub fn c(self: *Self) void {
        const step = self.b.step("c", "Build core as a c library");
        const static_lib = self.b.addLibrary(.{
            .name = self.b.fmt("rtcore", .{}),
            .root_module = self.module(.core),
            .linkage = .static,
        });

        const write_files = self.b.addWriteFiles();
        const bindings = @import("core/bindings.zig");
        const data = bindings.data(.c, self.b.allocator) catch |err| {
            std.debug.print("Failed to generate header: {any}", .{err});
            std.process.exit(1);
        };
        const header_path = write_files.add("rt_core.h", data.items);

        const install_header_file = self.b.addInstallHeaderFile(header_path, "rt_core.h");
        const install_static_lib = self.b.addInstallArtifact(static_lib, .{});

        install_header_file.step.dependOn(&write_files.step);
        step.dependOn(&install_static_lib.step);
        step.dependOn(&install_header_file.step);
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

        const ci = self.b.option(bool, "ci", "Running in CI") orelse false;

        if (ci) {
            const install_example = self.b.addInstallArtifact(example, .{});
            install_example.step.dependOn(self.b.getInstallStep());
            step.dependOn(&install_example.step);
        } else {
            const run_example = self.b.addRunArtifact(example);
            run_example.step.dependOn(self.b.getInstallStep());

            if (self.b.args) |args| {
                run_example.addArgs(args);
            }

            step.dependOn(&run_example.step);
        }
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

    pub fn wasm(self: *Self) void {
        const step = self.b.step("wasm", "Build core as a wasm module");

        const wasi = self.b.option(bool, "wasi", "If the module should target wasi") orelse false;
        const core = self.b.addModule("core_wasm", .{
            .root_source_file = self.b.path("core/lib.zig"),
            .target = self.b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = if (wasi) .wasi else .freestanding,
            }),
            .optimize = self.optimize,
        });

        const wasm_module = self.b.addExecutable(.{
            .name = self.b.fmt("rt_core", .{}),
            .root_module = core,
            .linkage = .static,
        });

        wasm_module.entry = .disabled;
        wasm_module.rdynamic = true;

        // TODO: Add options to configure these.
        wasm_module.global_base = 4096;
        wasm_module.stack_size = 16 * std.wasm.page_size;
        wasm_module.initial_memory = 64 * std.wasm.page_size;
        wasm_module.max_memory = 512 * std.wasm.page_size;

        const install_wasm_module = self.b.addInstallArtifact(wasm_module, .{});
        step.dependOn(&install_wasm_module.step);
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
        compile.root_module.addImport(@tagName(package), self.module(package));
    }

    fn module(self: *Self, comptime package: Package) *std.Build.Module {
        return self.b.modules.getPtr(@tagName(package)).?.*;
    }
};
