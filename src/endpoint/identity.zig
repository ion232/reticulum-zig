const std = @import("std");
const crypto = @import("src/crypto/crypto.zig");

const DhKeyPair = crypto.x25519.KeyPair;
const SignatureKeyPair = crypto.ed25519.KeyPair;

const Hash = @import("src/hash.zig").Hash;

pub const Identity = struct {
    const Self = @This();

    dh_public_key: [32]u8,
    sig_public_key: [32]u8,
    dh_secret_key: ?[32]u8,
    sig_secret_key: ?[32]u8,
    hash: Hash,

    pub fn from_public_key(dh_public_key: [32]u8, sig_public_key: [32]u8) Identity {
        return .{
            .dh_public_key = dh_public_key,
            .sig_public_key = sig_public_key,
            .hash = make_hash(dh_public_key, sig_public_key),
        };
    }

    pub fn has_secrets(self: *Self) bool {
        return self.dh_secret_key != null and self.sig_secret_key != null;
    }

    pub fn random() Identity {
        const dh_key_pair = DhKeyPair.generate();
        const sig_key_pair = SignatureKeyPair.generate();
        const hash = make_hash(dh_key_pair.public_key, sig_key_pair.public_key);

        return .{
            .dh_key_pair = dh_key_pair,
            .sig_key_pair = sig_key_pair,
            .hash = hash,
        };
    }

    fn make_hash(dh_pub_key: *const crypto.x25519.PublicKey, sig_pub_key: *const crypto.ed25519.PublicKey) Hash {
        return Hash.from_items(.{
            .dh_pub_key = dh_pub_key,
            .sig_pub_key = sig_pub_key,
        });
    }
};
