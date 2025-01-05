const Self = @This();

ptr: *anyopaque,
monotonicNanosFn: *const fn (ptr: *anyopaque) u64,

pub fn monotonicNanos(self: *Self) u64 {
    return self.monotonicNanosFn(self.ptr);
}
