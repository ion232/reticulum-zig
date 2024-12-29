const std = @import("std");
const crypto = @import("../crypto.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @import("../endpoint.zig").Endpoint;
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
        .table = Table.init(ally),
    };
}

pub fn add_endpoint(self: *Self, endpoint: *const Endpoint) void {}

const Entry = struct {
    timestamp: i64,
    expiry_time: i64,
    endpoint: Endpoint,
    hops: u8,
    origin: Hash,
    origin_interface: Interface.Id,
    packet_hash: Hash,
    public_keys: PublicKeys,
    ratchet: Ratchet,
    // noise: ...,
    // origin_announce: ...,
    application_data: []const u8,
};
