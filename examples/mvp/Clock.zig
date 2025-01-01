const rt = @import("reticulum");

pub const Unit = enum { s, ms, us, ns };

const Self = @This();

timestamp: u64,

pub fn init() Self {
    return .{
        .timestamp = 0,
    };
}

pub fn advance(self: *Self, count: u64, unit: Unit) void {
    const factor = switch (unit) {
        .s => 1,
        .ms => 1000,
        .us => 1_000_000,
        .ns => 1_000_000_000,
    };
    self.timestamp += (factor * count);
}

pub fn monotonicNanos(ptr: *anyopaque) u64 {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.timestamp;
}

pub fn clock(self: *Self) rt.System.Clock {
    return .{
        .ptr = self,
        .monotonicNanosFn = monotonicNanos,
    };
}
