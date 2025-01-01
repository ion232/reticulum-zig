const std = @import("std");
const crypto = @import("../crypto.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @import("Managed.zig");
const Identity = crypto.Identity;
const Interface = @import("../Interface.zig");
const Ratchet = Identity.Ratchet;
const PublicKeys = Identity.PublicKeys;
const Hash = crypto.Hash;
const Rng = @import("../System.zig").Rng;

const Self = @This();

ally: Allocator,
entries: std.StringHashMap(Entry),

pub fn init(ally: Allocator) Self {
    return .{
        .ally = ally,
        .entries = std.StringHashMap(Entry).init(ally),
    };
}

pub fn deinit(self: *Self) void {
    self.entries.deinit();
    self.* = undefined;
}

pub fn add(self: *Self, endpoint: Endpoint) Allocator.Error!void {
    try self.entries.put(endpoint.hash.bytes[0..], Entry{
        .endpoint = endpoint,
    });
}

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
