const std = @import("std");

pub const Id = u8;

const Self = @This();

access_code: ?[]const u8 = null,

// ptr: *anyopaque,
// sendFn: *const fn (ptr: *anyopaque) u64,

// fn send(self: *Self) u64 {
//     return self.sendFn(self.ptr);
// }
