const std = @import("std");
const Timer = std.time.Timer;

// Acts as an abstraction over certain sources of data.
pub const Sources = struct {
    rng: Rng,
    clock: Clock,

    pub fn default() !Sources {
        return .{
            // ion232: This is the equivalent of os.urandom in python.
            .rng = std.crypto.random,
            .clock = StdClock.clock(),
        };
    }
};

pub const Rng = std.Random;

pub const Clock = struct {
    ptr: *anyopaque,
    monotonicTimeFn: *const fn (ptr: *anyopaque) u64,

    fn monotonicTime(self: *Clock) u64 {
        return self.monotonicTimeFn(self.ptr);
    }
};

const StdClock = struct {
    timer: Timer,

    pub fn init() !StdClock {
        return .{
            .timer = try Timer.start(),
        };
    }

    pub fn monotonicTime(ptr: *anyopaque) u64 {
        const self: *StdClock = @ptrCast(@alignCast(ptr));
        return self.timer.read();
    }

    pub fn clock(self: *StdClock) Clock {
        return .{
            .ptr = self,
            .monotonicTimeFn = monotonicTime,
        };
    }
};
