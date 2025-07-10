const core = @import("reticulum");
const microzig = @import("microzig");
const rp2 = microzig.hal;

const Self = @This();

pub fn monotonicMicros(ptr: *anyopaque) u64 {
    _ = ptr;
    return rp2.time.get_time_since_boot().to_us();
}

pub fn clock(self: *Self) core.System.Clock {
    return .{
        .ptr = self,
        .monotonicMicrosFn = monotonicMicros,
    };
}
