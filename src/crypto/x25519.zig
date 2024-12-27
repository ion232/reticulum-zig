const std = @import("std");

pub usingnamespace std.crypto.dh.X25519;

pub const PublicKey = [std.crypto.dh.X25519.public_length]u8;
pub const SecretKey = [std.crypto.dh.X25519.secret_length]u8;
