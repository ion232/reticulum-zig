const std = @import("std");
const Aes = std.crypto.core.aes.Aes256;
const Pkcs7 = @import("pkcs7.zig").Impl;

const Self = @This();

pub const key_length = Aes.key_bits / 8;
pub const block_length = Aes.block.block_length;

pub fn encrypt(dst: []u8, src: []const u8, key: [key_length]u8, iv: [block_length]u8) []u8 {
    const context = Aes.initEnc(key);
    var previous: *const [block_length]u8 = &iv;
    var i: usize = 0;

    while (i + block_length <= src.len) : (i += block_length) {
        var current = Aes.block.fromBytes(src[i .. i + block_length][0..block_length]);
        const xored_block = current.xorBytes(previous);
        var out = dst[i .. i + block_length];
        context.encrypt(out[0..block_length], &xored_block);
        previous = out[0..block_length];
    }

    const last_block: *[block_length]u8 = dst[i .. i + block_length][0..block_length];
    if (i < src.len) {
        @memcpy(dst[i..src.len], src[i..src.len]);
    }
    const ciphertext = Pkcs7(block_length).pad(dst[0..src.len], dst);
    const xored_block = Aes.block.fromBytes(last_block).xorBytes(previous);
    context.encrypt(last_block, &xored_block);
    return ciphertext;
}

pub fn decrypt(dst: []u8, src: []const u8, key: [key_length]u8, iv: [block_length]u8) ![]const u8 {
    const context = Aes.initDec(key);
    var previous: *const [block_length]u8 = &iv;
    var i: usize = 0;

    std.debug.assert(src.len % block_length == 0);

    while (i + block_length <= src.len) : (i += block_length) {
        const current = src[i .. i + block_length][0..block_length];
        const out = dst[i .. i + block_length];
        context.decrypt(out[0..block_length], current);
        const plaintext = Aes.block.fromBytes(out[0..block_length]).xorBytes(previous);
        @memcpy(dst[i .. i + block_length], &plaintext);
        previous = current;
    }

    return try Pkcs7(block_length).unpad(dst[0..src.len]);
}

const t = std.testing;
const test_key = [Self.key_length]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0xF, 0xE, 0xD, 0xC, 0xB, 0xA, 0x9, 0x8, 0x7, 0x6, 0x5, 0x4, 0x3, 0x2, 0x1, 0x0, 0x8, 0x9, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF };
const test_iv = [Self.block_length]u8{ 0xF, 0xE, 0xD, 0xC, 0xB, 0xA, 0x9, 0x8, 0x7, 0x6, 0x5, 0x4, 0x3, 0x2, 0x1, 0x0 };

test "Encrypt and decrypt" {
    const initial_plaintext = "reticulum-zig!";
    var ciphertext_buffer: [2 * Self.block_length]u8 = undefined;

    const ciphertext = Self.encrypt(ciphertext_buffer[0..], initial_plaintext[0..], test_key, test_iv);
    try t.expect(ciphertext.len % Self.block_length == 0);
    try t.expect(!std.mem.eql(u8, initial_plaintext[0..], ciphertext[0..initial_plaintext.len]));

    var plaintext_buffer: [2 * Self.block_length]u8 = undefined;
    const plaintext = try Self.decrypt(plaintext_buffer[0..], ciphertext[0..], test_key, test_iv);

    try t.expect(plaintext.len == initial_plaintext.len);
    try t.expectEqualSlices(u8, plaintext, initial_plaintext);
}

test "Encrypt and decrypt empty" {
    const initial_plaintext = "";
    var ciphertext_buffer: [2 * Self.block_length]u8 = undefined;

    const ciphertext = Self.encrypt(ciphertext_buffer[0..], initial_plaintext[0..], test_key, test_iv);
    try t.expect(ciphertext.len == Self.block_length);

    var plaintext_buffer: [2 * Self.block_length]u8 = undefined;
    const plaintext = try Self.decrypt(plaintext_buffer[0..], ciphertext[0..], test_key, test_iv);

    try t.expect(plaintext.len == initial_plaintext.len);
    try t.expectEqualSlices(u8, plaintext, initial_plaintext);
}

test "Encrypt and decrypt of block length" {
    const initial_plaintext = "this is 16 chars";
    var ciphertext_buffer: [2 * Self.block_length]u8 = undefined;
    try t.expect(initial_plaintext.len == Self.block_length);

    const ciphertext = Self.encrypt(ciphertext_buffer[0..], initial_plaintext[0..], test_key, test_iv);
    try t.expect(ciphertext.len % Self.block_length == 0);
    try t.expect(!std.mem.eql(u8, initial_plaintext[0..], ciphertext[0..initial_plaintext.len]));

    var plaintext_buffer: [2 * Self.block_length]u8 = undefined;
    const plaintext = try Self.decrypt(plaintext_buffer[0..], ciphertext[0..], test_key, test_iv);

    try t.expect(plaintext.len == initial_plaintext.len);
    try t.expectEqualSlices(u8, plaintext, initial_plaintext);
}

test "Encrypt and decrypt of two block lengths" {
    const initial_plaintext = "this is a total of 32 chars wide";
    var ciphertext_buffer: [3 * Self.block_length]u8 = undefined;
    try t.expect(initial_plaintext.len == 2 * Self.block_length);

    const ciphertext = Self.encrypt(ciphertext_buffer[0..], initial_plaintext[0..], test_key, test_iv);
    try t.expect(ciphertext.len % Self.block_length == 0);
    try t.expect(!std.mem.eql(u8, initial_plaintext[0..], ciphertext[0..initial_plaintext.len]));

    var plaintext_buffer: [3 * Self.block_length]u8 = undefined;
    const plaintext = try Self.decrypt(plaintext_buffer[0..], ciphertext[0..], test_key, test_iv);

    try t.expect(plaintext.len == initial_plaintext.len);
    try t.expectEqualSlices(u8, plaintext, initial_plaintext);
}
