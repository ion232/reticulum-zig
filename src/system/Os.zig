const std = @import("std");
const Timer = std.time.Timer;
const System = @import("src/System.zig");

pub const Self = @This();

os_clock: Clock,
clock: System.Clock,
rng: System.Rng,

pub fn init() Clock.Error!Self {
    const os_clock = try Clock.init();
    return .{
        .os_clock = os_clock,
        .clock = os_clock.clock(),
        .rng = std.crypto.random,
    };
}

pub fn system(self: *const Self) System {
    return .{
        .clock = self.clock,
        .rng = self.rng,
    };
}

pub const Clock = struct {
    pub const Error = error{TimerUnsupported};

    timer: Timer,

    pub fn init() Error!Clock {
        return .{
            .timer = try Timer.start(),
        };
    }

    pub fn monotonicNanos(ptr: *anyopaque) u64 {
        const self: *Clock = @ptrCast(@alignCast(ptr));
        return self.timer.read();
    }

    pub fn clock(self: *Clock) System.Clock {
        return .{
            .ptr = self,
            .monotonicNanosFn = monotonicNanos,
        };
    }
};
