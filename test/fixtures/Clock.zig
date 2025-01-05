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
    const factor: u64 = switch (unit) {
        .s => 1,
        .ms => 1_000,
        .us => 1_000_000,
        .ns => 1_000_000_000,
    };
    self.timestamp += (factor * count);
}

pub fn monotonicMicros(ptr: *anyopaque) u64 {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.timestamp;
}

pub fn clock(self: *Self) rt.System.Clock {
    return .{
        .ptr = self,
        .monotonicMicrosFn = monotonicMicros,
    };
}
