const std = @import("std");
const mz = @import("microzig");

const devices = .{
    .pico,
};

pub fn build(b: *std.Build) void {
    inline for (devices) |device| {
        const DeviceSpec = Spec(device);
        const spec = DeviceSpec.init(b).?;
        const step = b.step(DeviceSpec.name, DeviceSpec.description);
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

        const name = switch (device) {
            .pico => "pico",
        };
        const description = switch (device) {
            .pico => "Raspberry Pi Pico",
        };
        const root_dir = switch (device) {
            .pico => "rpi/pico",
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
            const firmware = self.micro_build.add_firmware(.{
                .name = "reticulum-" ++ Self.name,
                .target = self.target,
                .optimize = b.standardOptimizeOption(.{}),
                .root_source_file = b.path(Self.root_dir ++ "/main.zig"),
            });

            const reticulum_core = b.dependency("reticulum", .{}).module("reticulum-core");
            firmware.add_app_import("reticulum", reticulum_core, .{});

            self.micro_build.install_firmware(firmware, .{});
            self.micro_build.install_firmware(firmware, .{ .format = .elf });
        }
    };
}

const Device = enum {
    pico,
};
