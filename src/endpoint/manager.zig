const std = @import("std");
const identity = @import("identity.zig");
const crypto = @import("src/crypto/crypto.zig");

const Allocator = std.mem.Allocator;
const Identity = identity.Identity;

pub const Manager = struct {
    identities: Identity,
    endpoints: Endpoints,

    pub fn init(ally: Allocator) void {
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
};

pub const Endpoints = struct {
    const Entry = struct {
        timestamp: i64,
        packet_hash: void,
        public_key: crypto.X25519.PublicKey,
        application_data: void,
    };

    map: std.StringHashMap(Entry),
};
