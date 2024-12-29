const std = @import("std");
const interface = @import("../interface.zig");
const Id = interface.Id;
const Config = interface.Config;
const Packet = @import("../packet.zig").Packet;
const RingBuffer = @import("../internal/RingBuffer.zig").RingBuffer;

pub const Target = union(enum) {
    single: interface.Id,
    all,
};

const Self = @This();

queues: std.AutoHashMap(Id, u8),
interfaces: std.AutoHashMap(Id, Config),

pub fn init() Self {}

pub fn receive(id: Id) void {
    //
}

pub fn send(target: Target, packet: Packet) void {
    //
}

const Queue = RingBuffer(Packet);

// ptr: *anyopaque,
// sendFn: *const fn (ptr: *anyopaque) u64,

// fn send(self: *Self) u64 {
//     return self.sendFn(self.ptr);
// }
