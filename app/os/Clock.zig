const std = @import("std");
const Timer = std.time.Timer;
const Clock = @import("../Clock.zig");

const Self = @This();

timer: Timer,

pub fn init() Timer.Error!Self {
    return .{
        .timer = try Timer.start(),
    };
}

pub fn monotonicMicros(ptr: *anyopaque) u64 {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.timer.read();
}

pub fn clock(self: *Self) Clock {
    return .{
        .ptr = self,
        .monotonicMicrosFn = monotonicMicros,
    };
}
