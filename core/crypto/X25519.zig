const std = @import("std");

pub usingnamespace std.crypto.dh.X25519;

const Self = @This();

pub const PublicKey = [Self.public_length]u8;
pub const SecretKey = [Self.secret_length]u8;

// Reimplemented from std lib to work on freestanding.

pub fn makeKeyPair(seed: [Self.seed_length]u8) !Self.KeyPair {
    var kp: Self.KeyPair = undefined;
    kp.secret_key = seed;
    kp.public_key = try Self.recoverPublicKey(seed);
    return kp;
}
