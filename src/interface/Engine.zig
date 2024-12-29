const std = @import("std");
const interface = @import("../interface.zig");
// const Packet = @import("node/Packet.zig").Packet;

pub const Target = union(enum) {
    single: interface.Id,
    all: void,
};

const Self = @This();

queues: std.AutoHashMap(interface.Id, u8),

pub fn init() Self {}

pub fn receive(id: interface.Id) void {
    //
}

pub fn send(target: Target) void {
    //
}

// ptr: *anyopaque,
// sendFn: *const fn (ptr: *anyopaque) u64,

// fn send(self: *Self) u64 {
//     return self.sendFn(self.ptr);
// }
