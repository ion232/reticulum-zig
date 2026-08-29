const std = @import("std");
const adt = @import("adt.zig");

const Allocator = std.mem.Allocator;
const Api = @import("Interface/Api.zig");
const BitRate = @import("unit.zig").BitRate;
const Event = @import("Node.zig").Event;
const Endpoint = @import("endpoint.zig").Managed;
const Hash = @import("crypto.zig").Hash;
const Packet = @import("packet.zig").Packet;
const PacketBuilder = @import("packet.zig").Builder;
const PacketFactory = @import("packet.zig").Factory;
const Payload = @import("packet.zig").Payload;
const Name = @import("endpoint/Name.zig");
const Fifo = @import("adt/Fifo.zig").Fifo;

pub const Id = usize;
pub const Mode = enum {
    full,
    point_to_point,
    access_point,
    roaming,
    boundary,
    gateway,

    pub fn routeLifetime(self: @This()) u64 {
        // TODO: Maybe have a Duration struct with these already defined.
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

pub const Directionality = enum {
    in,
    out,
    both,
};
pub const Incoming = Fifo(Event.In);
pub const Outgoing = Fifo(Event.Out);

pub const Error = Incoming.Error || Outgoing.Error || PacketFactory.Error || Allocator.Error;

const Self = @This();

// TODO: Account for interfaces that only receive packets and don't transmit.
// TODO: Rethink and refactor the event API. Most likely have an interface level API and a node level API.

id: Id,
incoming: Incoming,
outgoing: Outgoing,
storage: Packet.Storage,
mode: Mode,
directionality: Directionality,
bit_rate: ?BitRate,

pub fn init(
    config: Config,
    id: Id,
    incoming: Incoming,
    outgoing: Outgoing,
    packet_factory: PacketFactory,
) Self {
    return Self{
        .id = id,
        .incoming = incoming,
        .outgoing = outgoing,
        .packet_factory = packet_factory,
        .mode = config.mode,
        .directionality = config.directionality,
        .bit_rate = config.bit_rate,
    };
}

pub fn announce(ptr: *anyopaque, hash: Hash, app_data: []const u8) Error!void {
    try deliverEvent(ptr, Event.In{
        .task = .{
            .announce = .{
                .hash = hash,
                .app_data = app_data,
            },
        },
    });
}

pub fn plain(ptr: *anyopaque, name: Name, payload: Payload) Error!void {
    try deliverEvent(ptr, Event.In{
        .task = .{
            .plain = .{
                .name = name,
                .payload = payload,
            },
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
