const std = @import("std");
const Timer = std.time.Timer;

pub const Os = @import("system/Os.zig");

const Self = @This();

clock: Clock,
rng: Rng,

pub fn init(clock: Clock, rng: Rng) Self {
    return .{
        .clock = clock,
        .rng = rng,
    };
}

pub const Clock = struct {
    ptr: *anyopaque,
    monotonicNanosFn: *const fn (ptr: *anyopaque) u64,

    pub fn monotonicNanos(self: *Clock) u64 {
        return self.monotonicNanosFn(self.ptr);
    }
};

pub const Rng = std.Random;
