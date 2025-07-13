const std = @import("std");
const errors = std.crypto.errors;

const Bytes = @import("../data.zig").Bytes;
const X25519 = std.crypto.dh.X25519;
const Ed25519 = std.crypto.sign.Ed25519;
const Fernet = @import("Fernet.zig");
const Hash = @import("Hash.zig");
const Rng = @import("../System.zig").Rng;

const Hkdf = std.crypto.kdf.hkdf.HkdfSha256;
const X25519PublicKey = [X25519.public_length]u8;
const X25519SecretKey = [X25519.secret_length]u8;

const Self = @This();

pub const Error = error{
    MissingSecretKey,
} || errors.EncodingError || errors.IdentityElementError || errors.NonCanonicalError || errors.SignatureVerificationError || errors.KeyMismatchError || errors.WeakPublicKeyError;

pub const Ratchet = X25519PublicKey;
pub const PublicKeys = Public;
pub const Public = struct {
    dh: X25519PublicKey,
    signature: Ed25519.PublicKey,
};

const Secret = struct {
    dh: X25519SecretKey,
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

    const dh = try X25519.KeyPair.generateDeterministic(dh_seed);
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

pub fn encrypt(self: *const Self, rng: Rng, plaintext: []const u8, buffer: []u8, ratchet: ?[32]u8) []const u8 {
    var seed: [X25519.seed_length]u8 = undefined;
    rng.bytes(&seed);

    const ephemeral = try X25519.KeyPair.generateDeterministic(seed);
    const public_key = if (ratchet) |r| r else self.public.dh;
    @memcpy(buffer[0..ephemeral.public_key.len], &ephemeral.public_key);

    const shared_secret = try X25519.scalarmult(ephemeral.secret_key, public_key);
    const pseudorandom_key = Hkdf.extract(&self.hash.bytes, &shared_secret);

    const derived_key: [2 * Fernet.key_length]u8 = undefined;
    Hkdf.expand(&derived_key, &.{}, &pseudorandom_key);

    const signing_key = derived_key[0..Fernet.key_length];
    const encryption_key = derived_key[Fernet.key_length..];
    const fernet = Fernet.init(signing_key, encryption_key);
    const total_length = fernet.encrypt(rng, buffer[ephemeral.public_key.len..], plaintext);

    return buffer[0..total_length];
}

pub fn decrypt(self: *const Self, ciphertext: []const u8) void {
    //
}

pub fn sign(self: *const Self, bytes: Bytes) Error!Ed25519.Signature {
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
    return Hash.of(.{
        .dh = public.dh,
        .signature = public.signature.bytes,
    });
}

const t = std.testing;

test "encrypt-decrypt" {
    //
}

test "encrypt-decrypt-block-size" {
    //
}

test "valid-signature" {
    const allocator = t.allocator;
    var rng = std.crypto.random;
    const identity = try Self.random(&rng);

    var message = try Bytes.initCapacity(allocator, 0);
    defer message.deinit();

    try message.appendSlice("this is a message");
    const signature = try identity.sign(message);

    try signature.verify(message.items, identity.public.signature);
}

test "invalid-signature" {
    const allocator = t.allocator;
    var rng = std.crypto.random;
    const identity1 = try Self.random(&rng);
    const identity2 = try Self.random(&rng);

    var message = try Bytes.initCapacity(allocator, 0);
    defer message.deinit();

    try message.appendSlice("this is a message");
    const signature = try identity1.sign(message);

    try t.expectError(
        error.SignatureVerificationFailed,
        signature.verify(message.items, identity2.public.signature),
    );
}
