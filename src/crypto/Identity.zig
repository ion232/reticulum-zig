const X25519 = @import("X25519.zig");
const Ed25519 = @import("Ed25519.zig");
const Hash = @import("Hash.zig");
const Rng = @import("src/System.zig").Rng;

const Self = @This();

pub const PublicKeys = Public;
pub const Public = struct {
    dh: X25519.PublicKey,
    sign: Ed25519.PublicKey,
};

const Secret = struct {
    dh: X25519.SecretKey,
    sign: Ed25519.SecretKey,
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

pub fn has_secret(self: *Self) bool {
    return self.secret != null;
}

pub fn random(rng: Rng) Self {
    const dh_seed: [X25519.seed_length]u8 = undefined;
    const signature_seed: [Ed25519.KeyPair.seed_length]u8 = undefined;

    rng.bytes(&dh_seed);
    rng.bytes(&signature_seed);

    const dh = X25519.KeyPair.create(dh_seed);
    const sign = Ed25519.KeyPair.create(signature_seed);

    const public = Public{
        .dh = dh.public_key,
        .sign = sign.public_key,
    };
    const secret = Secret{
        .dh = dh.secret_key,
        .sign = sign.secret_key,
    };

    return .{
        .public = public,
        .secret = secret,
        .hash = make_hash(public),
    };
}

fn make_hash(public: *const Public) Hash {
    return Hash.from_items(.{
        .dh = public.dh,
        .sign = public.sign,
    });
}
