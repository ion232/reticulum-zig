const builtin = @import("builtin");
const std = @import("std");
const Aes = @import("Aes.zig");
const Rng = @import("../System.zig").Rng;
const Hmac = std.crypto.auth.hmac.sha2.HmacSha256;

const Self = @This();

pub const Error = error{VerificationFailed} || Aes.Error;

pub const SigningKey = [key_length]u8;
pub const EncryptionKey = [key_length]u8;

pub const key_length = Aes.key_length;

signing_key: SigningKey,
encryption_key: EncryptionKey,

pub fn init(signing_key: *const SigningKey, encryption_key: *const EncryptionKey) Self {
    return .{
        .signing_key = signing_key.*,
        .encryption_key = encryption_key.*,
    };
}

pub fn random(rng: Rng) Self {
    var self = Self{
        .signing_key = undefined,
        .encryption_key = undefined,
    };

    rng.bytes(&self.signing_key);
    rng.bytes(&self.encryption_key);

    return self;
}

pub fn encrypt(self: Self, rng: Rng, buffer: []u8, plaintext: []const u8) []const u8 {
    var iv: [Aes.block_length]u8 = undefined;
    rng.bytes(&iv);
    @memcpy(buffer[0..iv.len], &iv);

    const ciphertext = Aes.encrypt(buffer[iv.len..], plaintext, self.encryption_key, iv);
    const hmac_index = iv.len + ciphertext.len;
    const count = hmac_index + Hmac.mac_length;

    var hmac: [Hmac.mac_length]u8 = undefined;
    var hmac_gen = Hmac.init(&self.signing_key);
    hmac_gen.update(&iv);
    hmac_gen.update(ciphertext);
    hmac_gen.final(&hmac);

    @memcpy(buffer[hmac_index..count], &hmac);

    return buffer[0..count];
}

pub fn decrypt(self: Self, token: []const u8, buffer: []u8) Error![]const u8 {
    if (!self.verify(token)) {
        return Error.VerificationFailed;
    }

    const iv = token[0..Aes.block_length];
    const ciphertext = token[Aes.block_length .. token.len - Hmac.mac_length];

    return try Aes.decrypt(buffer, ciphertext, self.encryption_key, iv.*);
}

pub fn verify(self: Self, token: []const u8) bool {
    var computed_hmac: [Hmac.mac_length]u8 = undefined;
    var h = Hmac.init(&self.signing_key);

    const iv = token[0..Aes.block_length];
    const ciphertext = token[Aes.block_length .. token.len - Hmac.mac_length];
    const hmac = token[token.len - Hmac.mac_length ..];

    h.update(iv);
    h.update(ciphertext);
    h.final(&computed_hmac);

    return std.mem.eql(u8, hmac, &computed_hmac);
}

const t = std.testing;

test "init" {
    const signing_key = "123456789ab321001234cf8765432a10";
    const encryption_key = "fdecb432100ab12356789ab32100cdef";
    const fernet = Self.init(signing_key, encryption_key);

    try t.expectEqualSlices(u8, signing_key, &fernet.signing_key);
    try t.expectEqualSlices(u8, encryption_key, &fernet.encryption_key);
}

test "encrypt-decrypt" {
    const fernet = Self.random(std.crypto.random);
    const plaintext = "reticulum-zig!";
    var token: [5 * Aes.block_length]u8 = undefined;

    const result = fernet.encrypt(std.crypto.random, &token, plaintext);
    try t.expect(fernet.verify(result));
    try t.expect(!std.mem.eql(u8, plaintext[0..], token[0..plaintext.len]));

    var buffer: [token.len]u8 = undefined;
    const computed_plaintext = try fernet.decrypt(result, &buffer);
    try t.expectEqualSlices(u8, plaintext, computed_plaintext);
}

test "encrypt-decrypt-block-size" {
    const fernet = Self.random(std.crypto.random);
    const plaintext = "reticulum ⚡️";
    var token: [5 * Aes.block_length]u8 = undefined;
    try t.expect(plaintext.len == Aes.block_length);

    const result = fernet.encrypt(std.crypto.random, &token, plaintext);
    try t.expect(fernet.verify(result));
    try t.expect(!std.mem.eql(u8, plaintext[0..], token[0..plaintext.len]));

    var buffer: [token.len]u8 = undefined;
    const computed_plaintext = try fernet.decrypt(result, &buffer);
    try t.expectEqualSlices(u8, plaintext, computed_plaintext);
}
