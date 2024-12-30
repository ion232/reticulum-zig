const std = @import("std");
const interface = @import("../interface.zig");
const units = @import("../units.zig");

const Id = interface.Id;
const Config = interface.Config;
const Packet = @import("../packet.zig").Packet;
const RingBuffer = @import("../internal/RingBuffer.zig").RingBuffer;

const Self = @This();

access_code_size: usize,

pub fn init() Self {}

pub fn receive(id: Id, bit_rate: *const units.BitRate) void {
    //
}

pub fn send(packet: Packet) void {
    //
}

const Queue = RingBuffer(Packet);

// ptr: *anyopaque,
// sendFn: *const fn (ptr: *anyopaque) u64,

// fn send(self: *Self) u64 {
//     return self.sendFn(self.ptr);
// }
