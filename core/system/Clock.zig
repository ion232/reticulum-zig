const Self = @This();

ptr: *anyopaque,
monotonicMicrosFn: *const fn (ptr: *anyopaque) u64,

pub fn monotonicMicros(self: *Self) u64 {
    return self.monotonicMicrosFn(self.ptr);
}
