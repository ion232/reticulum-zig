const std = @import("std");
const crypto = @import("src/crypto.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @import("src/Endpoint.zig");
const PublicKeys = crypto.Identity.PublicKeys;
const Hash = crypto.Hash;

const Self = @This();

ally: Allocator,
identities: std.Arr,
endpoints: Endpoints,

pub fn init(ally: Allocator) Self {
    return .{
        .endpoints = Endpoints.init(ally),
    };
}

pub fn make_endpoint() *const Endpoint {
    // Does it accept links?
    // Do it return proofs?
    // Are ratchets enabled?
}

pub fn encrypt(endpoint: Endpoint, data: []u8) void {}

pub fn decrypt(endpoint: Endpoint, data: []u8) void {}

pub fn sign(endpoint: Endpoint, data: []u8) [16]u8 {}

const Endpoints = struct {
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

    map: std.StringHashMap(Entry),
};
