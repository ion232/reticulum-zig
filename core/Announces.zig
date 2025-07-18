const builtin = @import("builtin");
const std = @import("std");
const crypto = @import("crypto.zig");

const Allocator = std.mem.Allocator;
const Hash = crypto.Hash;
const Interface = @import("Interface.zig");
const Packet = @import("packet/Managed.zig");
const System = @import("System.zig");

const Self = @This();

pub const PacketOut = struct {
    packet: Packet,
    interface: Interface.Id,
};

const Entry = struct {
    timestamp: u64,
    retransmit_timeout: u64,
    retries: u8,
    hops: u8,
    packet: Packet,
    rebroadcasts: u8,
    should_block_rebroadcast: bool,
    previous_hop: Hash.Short,
    interface_id: Interface.Id,
};

const max_retries = 2;

ally: Allocator,
entries: std.StringArrayHashMap(Entry),
last_checked: u64,

pub fn init(ally: Allocator) Self {
    return .{
        .ally = ally,
        .entries = std.StringArrayHashMap(Entry).init(ally),
        .last_checked = 0,
    };
}

pub fn process(self: *Self, outgoing: *std.ArrayList(Packet), now: u64) !void {
    if (now <= self.last_checked + 1_000_000) return;

    var to_remove = std.ArrayList([]const u8).init(self.ally);
    var entries = self.entries.iterator();

    while (entries.next()) |e| {
        const key = e.key_ptr.*;
        const entry = e.value_ptr;

        if (entry.retries >= max_retries) {
            try to_remove.append(key);
        } else if (now > entry.retransmit_timeout) {
            if (entry.should_block_rebroadcast) {
                entry.packet.context = .path_response;
            }

            entry.packet.header.hops = entry.hops;
            try outgoing.append(entry.packet);
        }
    }

    for (to_remove.items) |k| {
        _ = self.entries.swapRemove(k);
    }

    self.last_checked = now;
}

pub fn add(
    self: *Self,
    endpoint: Hash.Short,
    packet: Packet,
    interface_id: Interface.Id,
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

pub fn remove(self: *Self, endpoint: Hash.Short) void {
    const key = self.entries.getKeyPtr(&endpoint) orelse return;
    _ = self.entries.swapRemove(key.*);
    self.ally.free(key.*);
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
