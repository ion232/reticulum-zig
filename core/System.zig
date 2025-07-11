const std = @import("std");

pub const Clock = struct {
    const Self = @This();

    ptr: *anyopaque,
    monotonicMicrosFn: *const fn (ptr: *anyopaque) u64,

    pub fn monotonicMicros(self: *Self) u64 {
        return self.monotonicMicrosFn(self.ptr);
    }
};

pub const Rng = std.Random;

pub const SimpleClock = struct {
    pub const Callback = *const fn () callconv(.c) u64;

    const Self = @This();

    monotonicMicrosFn: Callback,

    pub fn init(monotonicMicrosFn: Callback) Self {
        return .{
            .monotonicMicrosFn = monotonicMicrosFn,
        };
    }

    pub fn monotonicMicros(ptr: *anyopaque) u64 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.monotonicMicrosFn();
    }

    pub fn clock(self: *Self) Clock {
        return .{
            .ptr = self,
            .monotonicMicrosFn = monotonicMicros,
        };
    }
};

pub const SimpleRng = struct {
    pub const Callback = *const fn (buf: [*]u8, length: usize) callconv(.c) void;

    const Self = @This();

    rngFillFn: Callback,

    pub fn init(rngFillFn: Callback) Self {
        return .{
            .rngFillFn = rngFillFn,
        };
    }

    pub fn rngFill(ptr: *anyopaque, buf: []u8) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.rngFillFn(buf.ptr, buf.len);
    }

    pub fn rng(self: *Self) Rng {
        return .{
            .ptr = self,
            .fillFn = rngFill,
        };
    }
};

clock: Clock,
rng: Rng,
