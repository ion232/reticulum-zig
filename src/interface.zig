const std = @import("std");

const Self = @This();

ptr: *anyopaque,
sendFn: *const fn (ptr: *anyopaque) u64,

fn send(self: *Self) u64 {
    return self.sendFn(self.ptr);
}
