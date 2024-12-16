const std = @import("std");

const X25519 = std.crypto.dh.X25519;

pub const KeyPair = X25519.KeyPair;
pub const PublicKey = [X25519.public_length]u8;
pub const SecretKey = [X25519.secret_length]u8;
