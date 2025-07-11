const core = @import("core");
const std = @import("std");

pub const Clock = struct {
    const Timer = std.time.Timer;

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

    pub fn clock(self: *Self) core.System.Clock {
        return .{
            .ptr = self,
            .monotonicMicrosFn = monotonicMicros,
        };
    }
};
