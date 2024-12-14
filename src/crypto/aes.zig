const std = @import("std");

const Pkcs7 = @import("pkcs7.zig").Pkcs7;
const Aes128 = std.crypto.core.aes.Aes128;

pub const Aes = struct {
    pub const block_length = Aes128.block.block_length;
    pub const pkcs7 = Pkcs7(block_length);

    pub fn encrypt(dst: []u8, src: []const u8, key: [block_length]u8, iv: [block_length]u8) []u8 {
        const context = Aes128.initEnc(key);
        var previous: *const [block_length]u8 = &iv;
        var i: usize = 0;

        while (i + block_length <= src.len) : (i += block_length) {
            var current = Aes128.block.fromBytes(src[i .. i + block_length][0..block_length]);
            const xored_block = current.xorBytes(previous);
            var out = dst[i .. i + block_length];
            context.encrypt(out[0..block_length], &xored_block);
            previous = out[0..block_length];
        }

        const last_block: *[block_length]u8 = dst[i .. i + block_length][0..block_length];
        if (i < src.len) {
            @memcpy(dst[i..src.len], src[i..src.len]);
        }
        const ciphertext = pkcs7.pad(dst[0..src.len], dst);
        const xored_block = Aes128.block.fromBytes(last_block).xorBytes(previous);
        context.encrypt(last_block, &xored_block);
        return ciphertext;
    }

    pub fn decrypt(dst: []u8, src: []const u8, key: [block_length]u8, iv: [block_length]u8) ![]const u8 {
        const context = Aes128.initDec(key);
        var previous: *const [block_length]u8 = &iv;
        var i: usize = 0;

        std.debug.assert(src.len % block_length == 0);

        while (i + block_length <= src.len) : (i += block_length) {
            const current = src[i .. i + block_length][0..block_length];
            const out = dst[i .. i + block_length];
            context.decrypt(out[0..block_length], current);
            const plaintext = Aes128.block.fromBytes(out[0..block_length]).xorBytes(previous);
            @memcpy(dst[i .. i + block_length], &plaintext);
            previous = current;
        }

        return try pkcs7.unpad(dst[0..src.len]);
    }
};

const t = std.testing;

const test_key = [Aes.block_length]u8{ 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0x8, 0x9, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF };
const test_iv = [Aes.block_length]u8{ 0xF, 0xE, 0xD, 0xC, 0xB, 0xA, 0x9, 0x8, 0x7, 0x6, 0x5, 0x4, 0x3, 0x2, 0x1, 0x0 };

test "Encrypt and decrypt" {
    const initial_plaintext = "reticulum-zig!";
    var ciphertext_buffer: [2 * Aes.block_length]u8 = undefined;

    const ciphertext = Aes.encrypt(ciphertext_buffer[0..], initial_plaintext[0..], test_key, test_iv);
    try t.expect(ciphertext.len % Aes.block_length == 0);
    try t.expect(!std.mem.eql(u8, initial_plaintext[0..], ciphertext[0..initial_plaintext.len]));

    var plaintext_buffer: [2 * Aes.block_length]u8 = undefined;
    const plaintext = try Aes.decrypt(plaintext_buffer[0..], ciphertext[0..], test_key, test_iv);

    try t.expect(plaintext.len == initial_plaintext.len);
    try t.expectEqualSlices(u8, plaintext, initial_plaintext);
}

test "Encrypt and decrypt empty" {
    const initial_plaintext = "";
    var ciphertext_buffer: [2 * Aes.block_length]u8 = undefined;

    const ciphertext = Aes.encrypt(ciphertext_buffer[0..], initial_plaintext[0..], test_key, test_iv);
    try t.expect(ciphertext.len == Aes.block_length);

    var plaintext_buffer: [2 * Aes.block_length]u8 = undefined;
    const plaintext = try Aes.decrypt(plaintext_buffer[0..], ciphertext[0..], test_key, test_iv);

    try t.expect(plaintext.len == initial_plaintext.len);
    try t.expectEqualSlices(u8, plaintext, initial_plaintext);
}

test "Encrypt and decrypt on block boundary" {
    const initial_plaintext = "this is blk len!";
    var ciphertext_buffer: [2 * Aes.block_length]u8 = undefined;

    const ciphertext = Aes.encrypt(ciphertext_buffer[0..], initial_plaintext[0..], test_key, test_iv);
    try t.expect(ciphertext.len % Aes.block_length == 0);
    try t.expect(!std.mem.eql(u8, initial_plaintext[0..], ciphertext[0..initial_plaintext.len]));

    var plaintext_buffer: [2 * Aes.block_length]u8 = undefined;
    const plaintext = try Aes.decrypt(plaintext_buffer[0..], ciphertext[0..], test_key, test_iv);

    try t.expect(plaintext.len == initial_plaintext.len);
    try t.expectEqualSlices(u8, plaintext, initial_plaintext);
}
