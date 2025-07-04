const std = @import("std");
const crypto = @import("../crypto.zig");

const Allocator = std.mem.Allocator;
const Builder = @import("Builder.zig");
const Endpoint = @import("Managed.zig");
const Identity = crypto.Identity;
const Interface = @import("../Interface.zig");
const Ratchet = Identity.Ratchet;
const PublicKeys = Identity.PublicKeys;
const Hash = crypto.Hash;
const Rng = @import("../System.zig").Rng;

const Self = @This();

const Entry = struct {
    // timestamp: i64,
    // expiry_time: i64,
    endpoint: Endpoint,
    // hops: u8,
    // origin: Hash,
    // origin_interface: Interface.Id,
    // packet_hash: Hash,
    // public_keys: PublicKeys,
    // ratchet: Ratchet,
    // noise: ...,
    // origin_announce: ...,
    // application_data: []const u8,
};

ally: Allocator,
main: Endpoint,
entries: std.StringHashMap(Entry),

pub fn init(ally: Allocator, main: Endpoint) !Self {
    var entries = std.StringHashMap(Entry).init(ally);
    try entries.put(main.hash.bytes[0..], Entry{
        .endpoint = main,
    });

    return Self{
        .ally = ally,
        .main = main,
        .entries = entries,
    };
}

pub fn getPtr(self: *Self, hash: Hash) ?*const Endpoint {
    if (self.entries.get(hash.bytes[0..])) |entry| {
        return &entry.endpoint;
    }

    return null;
}

pub fn add(self: *Self, endpoint: *const Endpoint) !void {
    try self.entries.put(endpoint.hash.bytes[0..], Entry{
        .endpoint = try endpoint.clone(),
    });
}

pub fn deinit(self: *Self) void {
    var entries = self.entries.valueIterator();

    while (entries.next()) |entry| {
        entry.endpoint.deinit();
    }

    self.entries.deinit();
    self.* = undefined;
}
