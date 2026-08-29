const std = @import("std");
const crypto = @import("../crypto.zig");
const Packet = @import("../Packet.zig");

const Allocator = std.mem.Allocator;
const Hash = crypto.Hash;
const Identity = crypto.Identity;

pub const PublicIdentity = struct {
    dh: *Identity.X25519PublicKey,
    signature: *Identity.Ed25519PublicKey,
};

pub const Signature = [crypto.Ed25519.Signature.encoded_length]u8;

pub const Tag = enum { announce, raw, none };

pub const Announce = struct {
    pub const Noise = [5]u8;
    pub const Timestamp = [5]u8;

    public_identity: PublicIdentity,
    name_hash: *Hash.Name,
    noise: *Noise,
    timestamp: *Timestamp,
    ratchet: *crypto.Identity.Ratchet,
    signature: *Signature,
    application_data: []u8,
};

pub const Endpoints = union(Packet.Header.Flag.Endpoints) {
    //
};

handle: Packet.Storage.Handle,
header: *Packet.Header,
access_code: []u8,
endpoints: *Packet.Endpoints,
context: *Packet.Context,
payload: Payload,
