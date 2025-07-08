const core = @import("core");
const std = @import("std");

pub const Unit = enum {
    seconds,
    milliseconds,
    microseconds,
};

const Self = @This();

timestamp: u64,

pub fn init() Self {
    return .{
        .timestamp = 0,
    };
}

pub fn advance(self: *Self, count: u64, unit: Unit) void {
    const factor: u64 = switch (unit) {
        .seconds => 1_000_000,
        .milliseconds => 1_000,
        .microseconds => 1,
    };
    self.timestamp += (count * factor);
}

pub fn monotonicMicros(ptr: *anyopaque) u64 {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.timestamp;
}

pub fn clock(self: *Self) core.System.Clock {
    return .{
        .ptr = self,
        .monotonicMicrosFn = monotonicMicros,
    };
}
