const builtin = @import("builtin");
const std = @import("std");
const crypto = @import("crypto.zig");

const Allocator = std.mem.Allocator;
const Hash = crypto.Hash;
const InterfaceId = @import("Interface.zig").Id;
const Packet = @import("packet/Managed.zig");
const System = @import("System.zig");

const Self = @This();

const Entry = struct {
    timestamp: u64,
    retransmit_timeout: u64,
    retries: u8,
    hops: u8,
    packet: *Packet,
    rebroadcasts: u8,
    should_block_rebroadcast: bool,
    previous_hop: Hash.Short,
    interface_id: InterfaceId,
};

ally: Allocator,
entries: std.StringArrayHashMap(Entry),

pub fn init(ally: Allocator) Self {
    return .{
        .ally = ally,
        .entries = std.StringArrayHashMap(Entry).init(ally),
    };
}

pub fn add(
    self: *Self,
    endpoint: Hash.Short,
    packet: *Packet,
    interface_id: InterfaceId,
    hops: u8,
    retransmit_delay: u64,
    now: u64,
) !void {
    if (!self.entries.contains(&endpoint)) {
        const key = try self.ally.dupe(u8, &endpoint);

        try self.entries.put(key, .{
            .timestamp = now,
            .retransmit_timeout = now + retransmit_delay,
            .retries = 0,
            .hops = hops,
            .packet = packet,
            .rebroadcasts = 0,
            .should_block_rebroadcast = false,
            .previous_hop = packet.endpoints.endpoint(),
            .interface_id = interface_id,
        });
    }
}

pub fn getPtr(self: *Self, endpoint: Hash.Short) ?*Entry {
    return self.entries.getPtr(&endpoint);
}

pub fn deinit(self: Self) void {
    var entries = self.entries.iterator();
    while (entries.next()) |entry| {
        self.ally.free(entry.key_ptr.*);
    }
    self.entries.deinit();
    self.* = undefined;
}
