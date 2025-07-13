const std = @import("std");
const crypto = @import("crypto.zig");

const Allocator = std.mem.Allocator;
const Hash = crypto.Hash;
const Interface = @import("Interface.zig");
const Packet = @import("packet.zig").Managed;

const Self = @This();

pub const Entry = struct {
    const TimestampedNoise = struct {
        timestamp: u40,
        noise: [5]u8,
    };
    const Noises = std.AutoArrayHashMap(TimestampedNoise, void);

    source_interface: Interface.Id,
    next_hop: Hash.Short,
    hops: u8,
    last_seen: u64,
    expiry_time: u64,
    noises: Noises,
    latest_timestamp: u40,
    packet_hash: Hash,
    state: State,

    pub fn has(self: *const @This(), timestamp: u40, noise: [5]u8) bool {
        return self.noises.contains(.{
            .timestamp = timestamp,
            .noise = noise,
        });
    }
};

pub const State = enum {
    unknown,
    unresponsive,
    responsive,
};

ally: Allocator,
entries: std.StringArrayHashMap(Entry),

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .entries = std.StringArrayHashMap(Entry).init(ally),
    };
}

pub fn has(self: *const Self, endpoint: Hash.Short) bool {
    return self.get(endpoint) != null;
}

pub fn get(self: *const Self, endpoint: Hash.Short) ?*const Entry {
    return self.entries.getPtr(&endpoint);
}

pub fn setLastSeen(self: *Self, endpoint: Hash.Short, now: u64) void {
    if (self.entries.getPtr(&endpoint)) |entry| {
        entry.last_seen = now;
    }
}

pub fn setState(self: *Self, endpoint: Hash.Short, state: State) void {
    if (self.entries.getPtr(&endpoint)) |entry| {
        entry.state = state;
    }
}

pub fn updateFrom(self: *Self, packet: *const Packet, interface: *const Interface, now: u64) !void {
    const endpoint = packet.endpoints.endpoint();
    const next_hop = packet.endpoints.nextHop();
    const timestamp = packet.payload.announce.timestamp;
    const noise = packet.payload.announce.noise;

    var entry = Entry{
        .source_interface = interface.id,
        .next_hop = next_hop,
        .hops = packet.header.hops,
        .last_seen = now,
        .expiry_time = now + interface.mode.routeLifetime(),
        .noises = Entry.Noises.init(self.ally),
        .latest_timestamp = timestamp,
        .packet_hash = packet.hash(),
        .state = .unknown,
    };

    if (self.entries.getPtr(&endpoint)) |current_entry| {
        entry.noises = current_entry.noises;
        entry.latest_timestamp = @max(timestamp, entry.latest_timestamp);
    }

    try entry.noises.put(.{
        .timestamp = timestamp,
        .noise = noise,
    }, {});

    if (self.entries.getPtr(&endpoint)) |current_entry| {
        current_entry.* = entry;
    } else {
        const key = try self.ally.dupe(u8, &endpoint);
        try self.entries.put(key, entry);
    }
}

pub fn deinit(self: *Self) void {
    var entries = self.entries.iterator();
    while (entries.next()) |entry| {
        self.ally.free(entry.key_ptr.*);
        entry.value_ptr.noises.deinit();
    }
    self.entries.deinit();
    self.* = undefined;
}
