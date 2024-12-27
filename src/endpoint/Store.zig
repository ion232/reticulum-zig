const std = @import("std");
const crypto = @import("src/crypto.zig");

const Allocator = std.mem.Allocator;
const Public = crypto.Identity.PublicKeys;

const Self = @This();

ally: Allocator,
identities: std.Arr,
endpoints: Endpoints,

pub fn init(ally: Allocator) Self {
    return .{
        .endpoints = Endpoints.init(ally),
    };
}

pub fn make_endpoint() Endpoint {
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
        origin: LongHash,
        origin_interface: u8,
        packet_hash: Hash,
        public_keys: PublicKeys,
        // unique_bytes: ...,
        // origin_announce: ...,
        application_data: []const u8,
    };

    map: std.StringHashMap(Entry),
};
