const std = @import("std");

const Aes128 = std.crypto.core.aes.Aes128;

pub const Aes = struct {
    pub const block_length = Aes128.block.block_length;

    pub fn encrypt(dst: []u8, src: []const u8, key: [block_length]u8, iv: [block_length]u8) void {
        const context = Aes128.initEnc(key);
        var last: *const [block_length]u8 = &iv;
        var i: usize = 0;

        while (i + block_length <= src.len) : (i += block_length) {
            var current = Aes128.block.fromBytes(src[i .. i + block_length][0..block_length]);
            const xored_block = &current.xorBytes(last);
            var out = dst[i .. i + block_length];
            context.encrypt(out[0..block_length], xored_block);
            last = out[0..block_length];
        }
    }

    pub fn decrypt(dst: []u8, src: []const u8, key: [block_length]u8, iv: [block_length]u8) void {
        const context = Aes128.initDec(key);
        var last: *const [block_length]u8 = &iv;
        var i: usize = 0;

        while (i + block_length <= src.len) : (i += block_length) {
            const current = src[i .. i + block_length][0..block_length];
            const out = dst[i .. i + block_length];
            context.decrypt(out[0..block_length], current);
            const plaintext = Aes128.block.fromBytes(out[0..block_length]).xorBytes(last);
            @memcpy(dst[i .. i + block_length], &plaintext);
            last = current;
        }
    }
};
