const std = @import("std");
const Timer = std.time.Timer;

pub const Self = @This();

rng: Rng,
clock: Clock,

pub fn init(rng: Rng, clock: Clock) Self {
    return .{
        .rng = rng,
        .clock = clock,
    };
}

pub fn default() !Self {
    return .{
        // ion232: This is the equivalent of os.urandom in python.
        .rng = std.crypto.random,
        .clock = OsClock.clock(),
    };
}

pub const Rng = std.Random;

pub const Clock = struct {
    ptr: *anyopaque,
    monotonicNanosFn: *const fn (ptr: *anyopaque) u64,

    pub fn monotonicNanos(self: *Clock) u64 {
        return self.monotonicNanosFn(self.ptr);
    }
};

pub const OsClock = struct {
    timer: Timer,

    pub fn init() !OsClock {
        return .{
            .timer = try Timer.start(),
        };
    }

    pub fn monotonicNanos(ptr: *anyopaque) u64 {
        const self: *OsClock = @ptrCast(@alignCast(ptr));
        return self.timer.read();
    }

    pub fn clock(self: *OsClock) Clock {
        return .{
            .ptr = self,
            .monotonicNanosFn = monotonicNanos,
        };
    }
};
