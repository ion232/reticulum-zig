const std = @import("std");
const crypto = @import("src/crypto/crypto.zig");
const ed25519 = crypto.ed25519;
const x25519 = crypto.x25519;

const DhKeyPair = crypto.x25519.KeyPair;
const SignatureKeyPair = crypto.ed25519.KeyPair;
const Sha256 = std.crypto.hash.sha2.Sha256;

pub const Identity = struct {
    const Self = @This();

    dh_public_key: [32]u8,
    sig_public_key: [32]u8,
    dh_secret_key: ?[32]u8,
    sig_secret_key: ?[32]u8,
    short_hash: ShortHash,

    pub fn from_public_key(dh_public_key: [32]u8, sig_public_key: [32]u8) Identity {
        const short_hash = ShortHash.from_keys(dh_public_key, sig_public_key);
        return .{
            .dh_public_key = dh_public_key,
            .sig_public_key = sig_public_key,
            .short_hash = short_hash,
        };
    }

    pub fn has_secrets(self: *Self) bool {
        return self.dh_secret_key != null and self.sig_secret_key != null;
    }

    pub fn random() Identity {
        const dh_key_pair = DhKeyPair.generate();
        const sig_key_pair = SignatureKeyPair.generate();
        const short_hash = ShortHash.from_keys(dh_key_pair.public_key);

        return .{
            .dh_key_pair = dh_key_pair,
            .sig_key_pair = sig_key_pair,
            .short_hash = short_hash,
        };
    }
};

pub const ShortHash = struct {
    const length: usize = Sha256.digest_length / 2;

    bytes: [length]u8,

    pub fn from_keys(dh_pub_key: *const x25519.PublicKey, sig_pub_key: *const ed25519.PublicKey) ShortHash {
        var hash: [Sha256.digest_length]u8 = undefined;
        var hasher = Sha256.init(.{});
        hasher.update(dh_pub_key);
        hasher.update(sig_pub_key);
        hasher.final(hash[0..]);

        const bytes: [length]u8 = undefined;
        @memcpy(bytes[0..ShortHash.length], hash[0..ShortHash.length]);

        return .{
            .bytes = bytes,
        };
    }
};
