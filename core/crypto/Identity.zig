const std = @import("std");
const data = @import("../data.zig");
const errors = std.crypto.errors;

const X25519 = @import("X25519.zig");
const Ed25519 = std.crypto.sign.Ed25519;
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

pub fn fromPublic(public: Public) Self {
    return .{
        .public = public,
        .secret = null,
        .hash = makeHash(public),
    };
}

pub fn random(rng: *Rng) !Self {
    var dh_seed: [X25519.seed_length]u8 = undefined;
    var signature_seed: [Ed25519.KeyPair.seed_length]u8 = undefined;

    rng.bytes(&dh_seed);
    rng.bytes(&signature_seed);

    const dh = try X25519.makeKeyPair(dh_seed);
    const signature = try Ed25519.KeyPair.generateDeterministic(signature_seed);

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
        .hash = makeHash(public),
    };
}

// pub fn encrypt(self: *const Self, data: []u8) void {}

// pub fn decrypt(self: *const Self, data: []u8) void {}

pub fn sign(self: *const Self, bytes: data.Bytes) Error!Ed25519.Signature {
    if (self.secret) |secret| {
        const key_pair = Ed25519.KeyPair{
            .public_key = self.public.signature,
            .secret_key = secret.signature,
        };
        const noise = null;
        return try key_pair.sign(bytes.items, noise);
    }

    return Error.MissingSecretKey;
}

pub fn hasSecret(self: *Self) bool {
    return self.secret != null;
}

fn makeHash(public: Public) Hash {
    return Hash.ofItems(.{
        .dh = public.dh,
        .signature = public.signature.bytes,
    });
}
