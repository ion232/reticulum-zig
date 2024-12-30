const std = @import("std");
const interface = @import("../interface.zig");
const BitRate = @import("../units.zig").BitRate;

const Id = interface.Id;
const Config = interface.Config;
const Packet = @import("../packet.zig").Packet;
const RingBuffer = @import("../internal/RingBuffer.zig").RingBuffer;

const Self = @This();

config: Config,
queue: Queue,

pub fn init() Self {}

// pub fn receive(id: Id, bit_rate: *const BitRate) void {
//     //
// }

pub fn send(packet: Packet) void {
    //
}

const Queue = RingBuffer(Packet);
