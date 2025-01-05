const std = @import("std");
const errors = std.crypto.errors;
const X25519 = @import("X25519.zig");
const Ed25519 = @import("Ed25519.zig");
const Hash = @import("Hash.zig");
const Rng = @import("../System.zig").Rng;

const Self = @This();

pub const Error = error{
    MissingSecretKey,
} || errors.EncodingError || errors.IdentityElementError || errors.NonCanonicalError || errors.SignatureVerificationError || errors.KeyMismatchError || errors.WeakPublicKeyError;

pub const Ratchet = X25519.SecretKey;
pub const PublicKeys = Public;
pub const Public = struct {
    dh: X25519.PublicKey,
    signature: Ed25519.PublicKey,
};

const Secret = struct {
    dh: X25519.SecretKey,
    signature: Ed25519.SecretKey,
};

public: Public,
secret: ?Secret,
hash: Hash,

pub fn from_public(public: Public) Self {
    return .{
        .public = public,
        .secret = null,
        .hash = make_hash(public),
    };
}

pub fn random(rng: *Rng) !Self {
    var dh_seed: [X25519.seed_length]u8 = undefined;
    var signature_seed: [Ed25519.KeyPair.seed_length]u8 = undefined;

    rng.bytes(&dh_seed);
    rng.bytes(&signature_seed);

    const dh = try X25519.makeKeyPair(dh_seed);
    const signature = try Ed25519.makeKeyPair(signature_seed);

    const public = Public{
        .dh = dh.public_key,
        .signature = signature.public_key,
    };
    const secret = Secret{
        .dh = dh.secret_key,
        .signature = signature.secret_key,
    };

    return .{
        .public = public,
        .secret = secret,
        .hash = make_hash(public),
    };
}

// pub fn encrypt(self: *const Self, data: []u8) void {}

// pub fn decrypt(self: *const Self, data: []u8) void {}

pub fn signer(self: *const Self, rng: *Rng) Error!Ed25519.Signer {
    if (self.secret) |s| {
        const key_pair = Ed25519.KeyPair{
            .public_key = self.public.signature,
            .secret_key = s.signature,
        };
        var noise: [Ed25519.noise_length]u8 = undefined;
        rng.bytes(&noise);
        return try Ed25519.signer(key_pair, noise);
    }

    return Error.MissingSecretKey;
}

pub fn has_secret(self: *Self) bool {
    return self.secret != null;
}

fn make_hash(public: Public) Hash {
    return Hash.hash_items(.{
        .dh = public.dh,
        .signature = public.signature.bytes,
    });
}
