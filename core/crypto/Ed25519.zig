const std = @import("std");

pub usingnamespace std.crypto.sign.Ed25519;

const Self = @This();
const Sha512 = std.crypto.hash.sha2.Sha512;

// Reimplemented from std lib to work on freestanding.

pub fn makeKeyPair(seed: [Self.KeyPair.seed_length]u8) !Self.KeyPair {
    var az: [Sha512.digest_length]u8 = undefined;
    var h = Sha512.init(.{});
    h.update(&seed);
    h.final(&az);
    const pk_p = Self.Curve.basePoint.clampedMul(az[0..32].*) catch return error.IdentityElement;
    const pk_bytes = pk_p.toBytes();
    var sk_bytes: [Self.SecretKey.encoded_length]u8 = undefined;
    sk_bytes[0..seed.len].* = seed;
    sk_bytes[Self.KeyPair.seed_length..].* = pk_bytes;
    return Self.KeyPair{
        .public_key = Self.PublicKey.fromBytes(pk_bytes) catch unreachable,
        .secret_key = try Self.SecretKey.fromBytes(sk_bytes),
    };
}

pub fn signer(key_pair: Self.KeyPair, noise: [Self.noise_length]u8) !Self.Signer {
    if (!std.mem.eql(u8, &key_pair.secret_key.publicKeyBytes(), &key_pair.public_key.toBytes())) {
        return error.KeyMismatch;
    }
    const scalar_and_prefix = scalarAndPrefix(key_pair.secret_key);
    var h = Sha512.init(.{});
    h.update(&scalar_and_prefix.prefix);
    h.update(&noise);
    var nonce64: [64]u8 = undefined;
    h.final(&nonce64);
    const nonce = Self.Curve.scalar.reduce64(nonce64);

    return try makeSigner(scalar_and_prefix.scalar, nonce, key_pair.public_key);
}

fn scalarAndPrefix(self: Self.SecretKey) struct { scalar: Self.Curve.scalar.CompressedScalar, prefix: [32]u8 } {
    var az: [Sha512.digest_length]u8 = undefined;
    var h = Sha512.init(.{});
    h.update(&self.seed());
    h.final(&az);

    var s = az[0..32].*;
    Self.Curve.scalar.clamp(&s);

    return .{ .scalar = s, .prefix = az[32..].* };
}

fn makeSigner(scalar: Self.Curve.scalar.CompressedScalar, nonce: Self.Curve.scalar.CompressedScalar, public_key: Self.PublicKey) !Self.Signer {
    const r = try Self.Curve.basePoint.mul(nonce);
    const r_bytes = r.toBytes();

    var t: [64]u8 = undefined;
    t[0..32].* = r_bytes;
    t[32..].* = public_key.bytes;
    var h = Sha512.init(.{});
    h.update(&t);

    return Self.Signer{ .h = h, .scalar = scalar, .nonce = nonce, .r_bytes = r_bytes };
}
