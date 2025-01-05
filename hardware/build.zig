const std = @import("std");
const mz = @import("microzig");

const devices = .{
    .pico,
};

pub fn build(b: *std.Build) void {
    inline for (devices) |device| {
        const spec = Spec(device).init(b).?;
        const metadata = Spec(device).metadata;
        const step = b.step(metadata.name, metadata.description);
        spec.build(b);
        step.dependOn(spec.micro_build.builder.getInstallStep());
    }
}

fn Spec(comptime device: Device) type {
    return struct {
        const Self = @This();
        const MicroBuild = mz.MicroBuild(switch (device) {
            .pico => .{ .rp2xxx = true },
        });
        const Target = mz.Target;
        const metadata = switch (device) {
            .pico => .{
                .name = "pico",
                .description = "Raspberry Pi Pico",
                .root_dir = "rpi/pico",
            },
        };

        micro_build: *MicroBuild,
        target: *const Target,

        fn init(b: *std.Build) ?Self {
            const mz_dep = b.dependency("microzig", .{});

            switch (device) {
                .pico => {
                    const micro_build = MicroBuild.init(b, mz_dep) orelse return null;

                    return Self{
                        .micro_build = micro_build,
                        .target = micro_build.ports.rp2xxx.boards.raspberrypi.pico,
                    };
                },
            }
        }

        fn build(self: Self, b: *std.Build) void {
            const optimize = b.standardOptimizeOption(.{});

            const firmware = self.micro_build.add_firmware(.{
                .name = "reticulum-" ++ Self.metadata.name,
                .target = self.target,
                .optimize = optimize,
                .root_source_file = b.path(Self.metadata.root_dir ++ "/main.zig"),
            });

            const reticulum_core = b.dependency("reticulum", .{ .optimize = optimize }).module("reticulum-core");
            firmware.add_app_import("reticulum", reticulum_core, .{});

            self.micro_build.install_firmware(firmware, .{});
            self.micro_build.install_firmware(firmware, .{ .format = .elf });
        }
    };
}

const Device = enum {
    pico,
};
