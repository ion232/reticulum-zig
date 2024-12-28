const builtin = @import("builtin");
const std = @import("std");
const Aes = @import("Aes.zig");
const Rng = @import("../System.zig").Rng;
const Hmac = std.crypto.auth.hmac.sha2.HmacSha256;

const Self = @This();

pub const Error = error{
    VerificationFailed,
};

pub const SigningKey = [Aes.block_length]u8;
pub const EncryptionKey = [Aes.block_length]u8;

signing_key: SigningKey,
encryption_key: EncryptionKey,

pub fn init(signing_key: SigningKey, encryption_key: EncryptionKey) Self {
    return .{
        .signing_key = signing_key,
        .encryption_key = encryption_key,
    };
}

pub fn random(rng: Rng) Self {
    const self = Self{
        .signing_key = undefined,
        .encryption_key = undefined,
    };

    rng.bytes(self.signing_key);
    rng.bytes(self.encryption_key);

    return self;
}

pub fn encrypt(self: Self, rng: Rng, plaintext: []const u8, buffer: []u8) Token {
    var iv: [Aes.block_length]u8 = undefined;
    rng.bytes(&iv);

    const ciphertext = Aes.encrypt(buffer, plaintext, self.encryption_key, iv);

    var hmac: [Hmac.mac_length]u8 = undefined;
    var hmac_gen = Hmac.init(&self.signing_key);
    hmac_gen.update(&iv);
    hmac_gen.update(ciphertext);
    hmac_gen.final(&hmac);

    return .{
        .iv = iv,
        .ciphertext = ciphertext,
        .hmac = hmac,
    };
}

pub fn decrypt(self: Self, token: *const Token, buffer: []u8) Error![]const u8 {
    if (!self.verify(token)) {
        return Error.VerificationFailed;
    }

    return try Aes.decrypt(buffer, token.ciphertext, self.encryption_key, token.iv);
}

pub fn verify(self: Self, token: *const Token) bool {
    var hmac: [Hmac.mac_length]u8 = undefined;
    var hmac_gen = Hmac.init(&self.signing_key);
    hmac_gen.update(&token.iv);
    hmac_gen.update(token.ciphertext);
    hmac_gen.final(&hmac);

    return std.mem.eql(u8, &token.hmac, &hmac);
}

pub const Token = struct {
    iv: [Aes.block_length]u8,
    ciphertext: []const u8,
    hmac: [Hmac.mac_length]u8,
};

const t = std.testing;

test "init" {
    const signing_key = @as(u128, 0x0123456789ABCDEF0123456789ABCDEF);
    const encryption_key = @as(u128, 0xFEDCBA9876543210FEDCBA9876543210);

    const fernet = Self.init(signing_key, encryption_key);

    try t.expectEqual(signing_key, std.mem.bytesToValue(u128, &fernet.signing_key));
    try t.expectEqual(encryption_key, std.mem.bytesToValue(u128, &fernet.encryption_key));
}

test "Fernet - encrypt and decrypt" {
    const fernet = Self.random();
    const plaintext = "reticulum-zig!";
    var ciphertext: [2 * Aes.block_length]u8 = undefined;

    const token = fernet.encrypt(plaintext, &ciphertext);
    try t.expect(fernet.verify(&token));
    try t.expect(!std.mem.eql(u8, plaintext[0..], ciphertext[0..plaintext.len]));

    var buffer: [ciphertext.len]u8 = undefined;
    const computed_plaintext = try fernet.decrypt(&token, &buffer);
    try t.expectEqualSlices(u8, plaintext, computed_plaintext);
}

test "Fernet - encrypt and decrypt of block length" {
    const fernet = Self.random();
    const plaintext = "reticulum-zig :)";
    var ciphertext: [2 * Aes.block_length]u8 = undefined;
    t.expect(plaintext.len == Aes.block_length);

    const token = fernet.encrypt(plaintext, &ciphertext);
    try t.expect(fernet.verify(&token));
    try t.expect(!std.mem.eql(u8, plaintext[0..], ciphertext[0..plaintext.len]));

    var buffer: [ciphertext.len]u8 = undefined;
    const computed_plaintext = try fernet.decrypt(&token, &buffer);
    try t.expectEqualSlices(u8, plaintext, computed_plaintext);
}
