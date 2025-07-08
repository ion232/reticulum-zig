const std = @import("std");

// TODO: Add storage interface.

pub const Clock = struct {
    const Self = @This();

    ptr: *anyopaque,
    monotonicMicrosFn: *const fn (ptr: *anyopaque) u64,

    pub fn monotonicMicros(self: *Self) u64 {
        return self.monotonicMicrosFn(self.ptr);
    }
};

pub const Rng = std.Random;

clock: Clock,
rng: Rng,
