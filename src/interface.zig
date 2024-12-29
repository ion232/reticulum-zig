const std = @import("std");
const Packet = @import("node/Packet.zig").Packet;

pub const Id = u64;

const Self = @This();

access_code: ?[]const u8 = null,

pub fn init() Self {}

pub fn parse(self: *Self, raw_data: []const u8) Packet {}

pub fn transmit(self: *Self) void {}

// ptr: *anyopaque,
// sendFn: *const fn (ptr: *anyopaque) u64,

// fn send(self: *Self) u64 {
//     return self.sendFn(self.ptr);
// }
