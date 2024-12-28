const std = @import("std");
const crypto = @import("../crypto.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @import("../Endpoint.zig");
const Identity = crypto.Identity;
const PublicKeys = Identity.PublicKeys;
const Hash = crypto.Hash;
const Rng = @import("../System.zig").Rng;

const Self = @This();



ally: Allocator,
identities: std.ArrayList(Identity),
entries: std.StringHashMap(Entry),

pub fn init(ally: Allocator) Self {
    return .{
        .table = Table.init(ally),
    };
}

pub fn builder() Builder {

}

pub fn random(self: *Self, rng: *Rng) Allocator.Error!*const Endpoint {
    const identity = crypto.Identity.random(rng);
    const endpoint = try self.ally.create(Endpoint);
    endpoint.* = Endpoint.init(identity, .in, .single, "Something");
    return endpoint;
}

pub fn encrypt(endpoint: Endpoint, data: []u8) void {}

pub fn decrypt(endpoint: Endpoint, data: []u8) void {}

pub fn sign(endpoint: Endpoint, data: []u8) [16]u8 {}

const Table = struct {
    const Entry = struct {
        timestamp: i64,
        expiry_time: i64,
        hops: u8,
        origin: Hash,
        origin_interface: u8,
        packet_hash: Hash,
        public_keys: PublicKeys,
        // unique_bytes: ...,
        // origin_announce: ...,
        application_data: []const u8,
    };

    map: 
};
