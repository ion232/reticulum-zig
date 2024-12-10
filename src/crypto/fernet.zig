const std = @import("std");
const hw = @import("hw/hw.zig");
const pkcs7 = @import("pkcs7.zig");

const Aes = @import("aes.zig").Aes;
const Hmac = std.crypto.auth.hmac.sha2.HmacSha256;
const Sha256 = std.crypto.hash.sha2.Sha256;

/// ion232: Normally this token has a version and timestamp, but these are removed in Reticulum.
pub const Token = struct {
    iv: [Aes.block_length]u8,
    ciphertext: []u8,
    hmac: [Hmac.mac_length]u8,

    pub fn init(iv: [Aes.block_length]u8, ciphertext: []u8, hmac: [Hmac.mac_length]u8) Token {
        return .{
            .iv = iv,
            .ciphertext = ciphertext,
            .hmac = hmac,
        };
    }

    pub fn verify(self: *Token) bool {
        const digest: [Hmac.mac_length]u8 = undefined;
        const token_slice: []u8 = std.mem.asBytes(self);
        const token_data_len = token_slice.len - @sizeOf(Token.hmac);
        Hmac.create(digest, token_slice[0..token_data_len], self.signing_key);
        return self.hmac == digest;
    }
};

pub const Fernet = struct {
    signing_key: [Aes.block_length]u8,
    encryption_key: [Aes.block_length]u8,

    pub fn init(signing_key: u128, encryption_key: u128) Fernet {
        var signing_bytes: [Aes.block_length]u8 = undefined;
        var encryption_bytes: [Aes.block_length]u8 = undefined;

        std.mem.writeInt(u128, &signing_bytes, signing_key, std.builtin.Endian.big);
        std.mem.writeInt(u128, &encryption_bytes, encryption_key, std.builtin.Endian.big);

        return .{
            .signing_key = signing_bytes,
            .encryption_key = encryption_bytes,
        };
    }

    pub fn random() Fernet {
        return .{
            .signing_key = hw.rand.int(u128),
            .encryption_key = hw.rand.int(u128),
        };
    }

    pub fn encrypt(self: Fernet, token: *Token, plaintext: *std.ArrayList(u8)) !void {
        try pkcs7.pad(plaintext, Aes.block_length);
        std.debug.assert(token.ciphertext.len >= plaintext.items.len);

        hw.rand.bytes(&token.iv);
        Aes.encrypt(token.ciphertext, plaintext.items, self.encryption_key, token.iv);

        const token_slice: []u8 = std.mem.asBytes(token);
        const token_data_len = token_slice.len - @sizeOf(Token.hmac);
        Hmac.create(token.hmac_digest, token_slice[0..token_data_len], self.signing_key);
    }

    pub fn decrypt(self: Fernet, plaintext: *std.ArrayList(u8), token: *Token) !void {
        if (!token.verify()) {
            return;
        }

        try plaintext.ensureTotalCapacity(token.ciphertext.len);
        try plaintext.expandToCapacity();

        Aes.decrypt(plaintext.items, token.ciphertext, self.encryption_key, token.iv);
        try pkcs7.unpad(plaintext, Aes.block_length);
    }
};

test "Fernet - initialize with keys" {
    const signing_key = @as(u128, 0x0123456789ABCDEF0123456789ABCDEF);
    const encryption_key = @as(u128, 0xFEDCBA9876543210FEDCBA9876543210);

    const f = Fernet.init(signing_key, encryption_key);

    try std.testing.expectEqual(signing_key, std.mem.bytesToValue(u128, &f.signing_key));
    try std.testing.expectEqual(encryption_key, std.mem.bytesToValue(u128, &f.encryption_key));
}

test "Fernet - initialize with random keys" {
    const f1 = Fernet.random();
    const f2 = Fernet.random();

    try std.testing.expect(!std.mem.eql(u8, &f1.signing_key, &f2.signing_key));
    try std.testing.expect(!std.mem.eql(u8, &f1.encryption_key, &f2.encryption_key));
}

test "Token - initialization and verification" {
    const allocator = std.testing.allocator;

    var iv: [Aes.block_length]u8 = undefined;
    hw.rand.bytes(&iv);

    const ciphertext = try allocator.alloc(u8, 32);
    defer allocator.free(ciphertext);
    hw.rand.bytes(ciphertext);

    var hmac: [Hmac.mac_length]u8 = undefined;
    hw.rand.bytes(&hmac);

    var token = Token.init(iv, ciphertext, hmac);

    try std.testing.expectEqualSlices(u8, &iv, &token.iv);
    try std.testing.expectEqualSlices(u8, ciphertext, token.ciphertext);
    try std.testing.expectEqualSlices(u8, &hmac, &token.hmac);
}

test "Fernet - encrypt and decrypt" {
    const allocator = std.testing.allocator;
    const f = Fernet.random();

    // Create test data
    var plaintext = std.ArrayList(u8).init(allocator);
    defer plaintext.deinit();
    try plaintext.appendSlice("Hello, World!");

    const ciphertext = try allocator.alloc(u8, 32);
    defer allocator.free(ciphertext);

    // Create token and encrypt
    var token = Token.init(undefined, ciphertext, undefined);
    try f.encrypt(&token, &plaintext);

    // Verify token
    try std.testing.expect(token.verify());

    // Decrypt and verify result
    var decrypted = std.ArrayList(u8).init(allocator);
    defer decrypted.deinit();

    try f.decrypt(&decrypted, &token);
    try std.testing.expectEqualSlices(u8, "Hello, World!", decrypted.items);
}

test "Fernet - tampered token detection" {
    const allocator = std.testing.allocator;
    const f = Fernet.random();

    // Create test data
    var plaintext = std.ArrayList(u8).init(allocator);
    defer plaintext.deinit();
    try plaintext.appendSlice("Secret Message");

    const ciphertext = try allocator.alloc(u8, 32);
    defer allocator.free(ciphertext);

    // Create token and encrypt
    var token = Token.init(undefined, ciphertext, undefined);
    try f.encrypt(&token, &plaintext);

    // Tamper with ciphertext
    token.ciphertext[0] ^= 1;

    // Verify token detects tampering
    try std.testing.expect(!token.verify());

    // Attempt to decrypt should fail
    var decrypted = std.ArrayList(u8).init(allocator);
    defer decrypted.deinit();

    try std.testing.expectError(error.InvalidToken, f.decrypt(&decrypted, &token));
}

test "Fernet - different key pairs" {
    const allocator = std.testing.allocator;
    const f1 = Fernet.random();
    const f2 = Fernet.random();

    // Create test data
    var plaintext = std.ArrayList(u8).init(allocator);
    defer plaintext.deinit();
    try plaintext.appendSlice("Test Message");

    const ciphertext = try allocator.alloc(u8, 32);
    defer allocator.free(ciphertext);

    // Encrypt with first key
    var token = Token.init(undefined, ciphertext, undefined);
    try f1.encrypt(&token, &plaintext);

    // Attempt to decrypt with different key
    var decrypted = std.ArrayList(u8).init(allocator);
    defer decrypted.deinit();

    try std.testing.expectError(error.InvalidToken, f2.decrypt(&decrypted, &token));
}

test "Fernet - large data" {
    const allocator = std.testing.allocator;
    const f = Fernet.random();

    // Create large test data
    var plaintext = std.ArrayList(u8).init(allocator);
    defer plaintext.deinit();

    for (0..1000) |i| {
        try plaintext.append(@intCast(i % 256));
    }

    const ciphertext = try allocator.alloc(u8, 1024);
    defer allocator.free(ciphertext);

    // Encrypt and decrypt
    var token = Token.init(undefined, ciphertext, undefined);
    try f.encrypt(&token, &plaintext);

    var decrypted = std.ArrayList(u8).init(allocator);
    defer decrypted.deinit();

    try f.decrypt(&decrypted, &token);
    try std.testing.expectEqualSlices(u8, plaintext.items, decrypted.items);
}
