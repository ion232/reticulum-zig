const std = @import("std");

pub const KeyPair = X25519.KeyPair;
pub const PublicKey = [X25519.public_length]u8;

const X25519 = std.crypto.dh.X25519;
