const std = @import("std");
const data = @import("data.zig");

pub const Manager = @import("interface/Manager.zig");

const Allocator = std.mem.Allocator;
const BitRate = @import("unit.zig").BitRate;
const Event = @import("Node.zig").Event;
const Endpoint = @import("endpoint.zig").Managed;
const Hash = @import("crypto.zig").Hash;
const Packet = @import("packet.zig").Packet;
const PacketBuilder = @import("packet.zig").Builder;
const PacketFactory = @import("packet.zig").Factory;
const Payload = @import("packet.zig").Payload;
const Name = @import("endpoint/Name.zig");
const ThreadSafeFifo = @import("internal/ThreadSafeFifo.zig").ThreadSafeFifo;

pub const Id = usize;
pub const Mode = enum {
    full,
    point_to_point,
    access_point,
    roaming,
    boundary,
    gateway,

    pub fn routeLifetime(self: @This()) u64 {
        const one_day = std.time.us_per_day;
        const six_hours = 6 * std.time.us_per_hour;
        const seven_weeks = 7 * std.time.us_per_week;

        return switch (self) {
            .access_point => one_day,
            .roaming => six_hours,
            else => seven_weeks,
        };
    }
};
pub const Directionality = enum { in, out, full };
pub const Incoming = ThreadSafeFifo(Event.In);
pub const Outgoing = ThreadSafeFifo(Event.Out);
pub const Config = struct {
    name: []const u8 = "unknown",
    access_code: ?[]const u8 = null,
    mode: Mode = .full,
    directionality: Directionality = .full,
    initial_bit_rate: BitRate = BitRate.default,
    max_held_packets: usize = 1000,
};

pub const Error = Incoming.Error || Outgoing.Error || PacketFactory.Error || Allocator.Error;

const Self = @This();

// TODO: Account for interfaces that only receive packets and don't transmit.
// TODO: Find a less error prone way to define the API.
// TODO: Rethink and refactor the event API.

ally: Allocator,
id: Id,
incoming: *Incoming,
outgoing: *Outgoing,
packet_factory: PacketFactory,
mode: Mode,
directionality: Directionality,

pub fn init(
    ally: Allocator,
    config: Config,
    id: Id,
    incoming: *Incoming,
    outgoing: *Outgoing,
    packet_factory: PacketFactory,
) Self {
    return Self{
        .ally = ally,
        .id = id,
        .incoming = incoming,
        .outgoing = outgoing,
        .packet_factory = packet_factory,
        .mode = config.mode,
        .directionality = config.directionality,
    };
}

pub fn announce(ptr: *anyopaque, hash: Hash, app_data: ?data.Bytes) Error!void {
    try deliverEvent(ptr, Event.In{
        .announce = .{
            .hash = hash,
            .app_data = app_data,
        },
    });
}

pub fn plain(ptr: *anyopaque, name: Name, payload: Payload) Error!void {
    try deliverEvent(ptr, Event.In{
        .plain = .{
            .name = name,
            .payload = payload,
        },
    });
}

pub fn deliverRawPacket(ptr: *anyopaque, bytes: []const u8) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const packet = try self.packet_factory.fromBytes(bytes);
    try deliverPacket(ptr, packet);
}

pub fn deliverPacket(ptr: *anyopaque, packet: Packet) !void {
    try deliverEvent(ptr, .{ .packet = packet });
}

pub fn deliverEvent(ptr: *anyopaque, event: Event.In) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.incoming.push(event);
}

pub fn collectEvent(ptr: *anyopaque) ?Event.Out {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.outgoing.pop();
}

pub fn deinit(self: *Self) void {
    self.incoming.deinit();
    self.outgoing.deinit();
    self.ally.destroy(self.incoming);
    self.ally.destroy(self.outgoing);
    self.* = undefined;
}

pub fn api(self: *Self) Api {
    return .{
        .ptr = self,
        .announceFn = announce,
        .plainFn = plain,
        .deliverRawPacketFn = deliverRawPacket,
        .deliverPacketFn = deliverPacket,
        .deliverEventFn = deliverEvent,
        .collectEventFn = collectEvent,
    };
}

pub const Api = struct {
    ptr: *anyopaque,
    announceFn: *const fn (ptr: *anyopaque, hash: Hash, app_data: ?data.Bytes) Error!void,
    plainFn: *const fn (ptr: *anyopaque, name: Name, payload: Payload) Error!void,
    deliverRawPacketFn: *const fn (ptr: *anyopaque, raw_bytes: []const u8) Error!void,
    deliverPacketFn: *const fn (ptr: *anyopaque, packet: Packet) Error!void,
    deliverEventFn: *const fn (ptr: *anyopaque, event: Event.In) Error!void,
    collectEventFn: *const fn (ptr: *anyopaque) ?Event.Out,

    pub fn announce(self: *@This(), hash: Hash, app_data: ?data.Bytes) Error!void {
        return self.announceFn(self.ptr, hash, app_data);
    }

    pub fn plain(self: *@This(), name: Name, payload: Payload) Error!void {
        return self.plainFn(self.ptr, name, payload);
    }

    pub fn deliverRawPacket(self: *@This(), raw_bytes: []const u8) Error!void {
        return self.deliverRawPacketFn(self.ptr, raw_bytes);
    }

    pub fn deliverPacket(self: *@This(), packet: Packet) Error!void {
        return self.deliverPacketFn(self.ptr, packet);
    }

    pub fn deliverEvent(self: *@This(), event: Event.In) Error!void {
        return self.deliverEventFn(self.ptr, event);
    }

    pub fn collectEvent(self: *@This()) ?Event.Out {
        return self.collectEventFn(self.ptr);
    }
};
