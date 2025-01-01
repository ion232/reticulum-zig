const std = @import("std");
const interface = @import("../interface.zig");
const BitRate = @import("../units.zig").BitRate;

const Allocator = std.mem.Allocator;
const Id = interface.Id;
const Config = interface.Config;
const Element = @import("../Node.zig").Element;
const Endpoint = @import("../endpoint.zig").Managed;
const Hash = @import("../crypto.zig").Hash;
const Packet = @import("../packet.zig").Packet;
const PacketBuilder = @import("../packet.zig").Builder;
const PacketFactory = @import("../packet.zig").Factory;
const RingBuffer = @import("../internal/RingBuffer.zig").RingBuffer;
const ThreadSafeRingBuffer = @import("../internal/ThreadSafeRingBuffer.zig").ThreadSafeRingBuffer;

// Probably rework this file.

pub const Incoming = ThreadSafeRingBuffer(Element.In);
pub const Outgoing = ThreadSafeRingBuffer(Element.Out);

pub const Error = Incoming.Error || Outgoing.Error || PacketFactory.Error || Allocator.Error;

const Self = @This();

ally: Allocator,
id: Id,
incoming: *Incoming,
outgoing: *Outgoing,
for_collection: RingBuffer(Packet),
packet_factory: PacketFactory,
// TODO: Replace this with an announce handling class potentially.
bit_rate: BitRate,

pub fn init(
    ally: Allocator,
    config: Config,
    id: Id,
    incoming: *Incoming,
    outgoing: *Outgoing,
    packet_factory: PacketFactory,
) !Self {
    return Self{
        .ally = ally,
        .id = id,
        .incoming = incoming,
        .outgoing = outgoing,
        .for_collection = try RingBuffer(Packet).init(ally, config.max_held_packets),
        .packet_factory = packet_factory,
        .bit_rate = config.initial_bit_rate,
    };
}

pub fn deliver_raw(ptr: *anyopaque, bytes: []const u8) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const packet = try self.packet_factory.from_bytes(bytes);
    try deliver(ptr, packet);
}

pub fn deliver(ptr: *anyopaque, packet: Packet) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.incoming.push(.{ .packet = packet });
}

pub fn send(ptr: *anyopaque, packet: Packet) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.outgoing.push(.{ .packet = packet });
}

pub fn collect(ptr: *anyopaque, current_bit_rate: BitRate) ?Packet {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.bit_rate = current_bit_rate;
    return self.for_collection.pop();
}

pub fn api(self: *Self) Api {
    return Api{
        .ptr = self,
        .deliverRawFn = deliver_raw,
        .deliverFn = deliver,
        .sendFn = send,
        .collectFn = collect,
    };
}

pub const Api = struct {
    ptr: *anyopaque,
    deliverRawFn: *const fn (ptr: *anyopaque, raw_bytes: []const u8) Error!void,
    deliverFn: *const fn (ptr: *anyopaque, packet: Packet) Error!void,
    sendFn: *const fn (ptr: *anyopaque, packet: Packet) Error!void,
    collectFn: *const fn (ptr: *anyopaque, current_bit_rate: BitRate) ?Packet,

    pub fn announce(self: *@This(), endpoint: *const Endpoint, application_data: ?[]const u8) Error!void {
        const engine: *Self = @ptrCast(@alignCast(self.ptr));
        const packet = try engine.packet_factory.make_announce(endpoint, application_data);
        try self.send(packet);
    }

    // pub fn data(self: *@This(), endpoint_hash: Hash.Short, data: []const u8) !void {}

    pub fn deliver_raw(self: *@This(), raw_bytes: []const u8) Error!void {
        return self.deliverRawFn(self.ptr, raw_bytes);
    }

    pub fn deliver(self: *@This(), packet: Packet) Error!void {
        return self.deliverFn(self.ptr, packet);
    }

    pub fn send(self: *@This(), packet: Packet) Error!void {
        return self.sendFn(self.ptr, packet);
    }

    pub fn collect(self: *@This(), current_bit_rate: BitRate) ?Packet {
        return self.collectFn(self.ptr, current_bit_rate);
    }

    // Should I use this, or use the packet factory instead?
    // pub fn builder(self: *@This()) PacketBuilder {}
};
