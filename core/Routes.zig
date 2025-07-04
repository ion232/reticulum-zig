const std = @import("std");
const crypto = @import("crypto.zig");

const Allocator = std.mem.Allocator;
const Hash = crypto.Hash;
const Interface = @import("Interface.zig");
const Packet = @import("packet.zig").Managed;

const Self = @This();

const Entry = struct {
    timestamp: u64,
    interface_id: Interface.Id,
    next_hop: Hash.Short,
    hops: u8,
};

ally: Allocator,
entries: std.StringHashMap(Entry),

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .entries = std.StringHashMap(Entry).init(ally),
    };
}

pub fn hops(self: *Self, endpoint: Hash.Short) !?u8 {
    if (self.entries.get(&endpoint)) |entry| {
        return entry.hops;
    }

    return null;
}

pub fn update_from(self: *Self, packet: *const Packet, interface: *const Interface, now: u64) !void {
    const endpoint = packet.endpoints.endpoint();
    const next_hop = packet.endpoints.nextHop();

    try self.entries.put(&endpoint, Entry{
        .timestamp = now,
        .interface_id = interface.id,
        .next_hop = next_hop,
        .hops = packet.header.hops,
    });
}

pub fn deinit(self: *Self) void {
    self.entries.deinit();
    self.* = undefined;
}
