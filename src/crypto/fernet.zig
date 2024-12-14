const builtin = @import("builtin");
const std = @import("std");
const aes = @import("aes.zig");
const hw = @import("src/hw/hw.zig");

const Aes = aes.Aes;
const Hmac = std.crypto.auth.hmac.sha2.HmacSha256;

pub const Fernet = struct {
    signing_key: [Aes.block_length]u8,
    encryption_key: [Aes.block_length]u8,

    pub fn init(signing_key: u128, encryption_key: u128) Fernet {
        var signing_bytes: [Aes.block_length]u8 = undefined;
        var encryption_bytes: [Aes.block_length]u8 = undefined;

        const endian = builtin.cpu.arch.endian();
        std.mem.writeInt(u128, &signing_bytes, signing_key, endian);
        std.mem.writeInt(u128, &encryption_bytes, encryption_key, endian);

        return .{
            .signing_key = signing_bytes,
            .encryption_key = encryption_bytes,
        };
    }

    pub fn random() Fernet {
        const signing_key = hw.rand.int(u128);
        const encryption_key = hw.rand.int(u128);
        return init(signing_key, encryption_key);
    }

    pub fn encrypt(self: Fernet, plaintext: []const u8, buffer: []u8) Token {
        var iv: [Aes.block_length]u8 = undefined;
        hw.rand.bytes(&iv);

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

    pub fn decrypt(self: Fernet, token: *const Token, buffer: []u8) ![]const u8 {
        if (!self.verify(token)) {
            return FernetError.VerificationFailed;
        }

        return try Aes.decrypt(buffer, token.ciphertext, self.encryption_key, token.iv);
    }

    pub fn verify(self: Fernet, token: *const Token) bool {
        var hmac: [Hmac.mac_length]u8 = undefined;
        var hmac_gen = Hmac.init(&self.signing_key);
        hmac_gen.update(&token.iv);
        hmac_gen.update(token.ciphertext);
        hmac_gen.final(&hmac);

        return std.mem.eql(u8, &token.hmac, &hmac);
    }
};

pub const Token = struct {
    iv: [Aes.block_length]u8,
    ciphertext: []const u8,
    hmac: [Hmac.mac_length]u8,
};

pub const FernetError = error{
    VerificationFailed,
};

const t = std.testing;

test "init" {
    const signing_key = @as(u128, 0x0123456789ABCDEF0123456789ABCDEF);
    const encryption_key = @as(u128, 0xFEDCBA9876543210FEDCBA9876543210);

    const fernet = Fernet.init(signing_key, encryption_key);

    try t.expectEqual(signing_key, std.mem.bytesToValue(u128, &fernet.signing_key));
    try t.expectEqual(encryption_key, std.mem.bytesToValue(u128, &fernet.encryption_key));
}

test "Fernet - encrypt and decrypt" {
    const fernet = Fernet.random();
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
    const fernet = Fernet.random();
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
