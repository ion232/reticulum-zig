const std = @import("std");
const core_aes = std.crypto.core.aes;

const Aes128 = core_aes.Aes128;
const AesEncryptCtx = core_aes.AesEncryptCtx(Aes128);
const AesDecryptCtx = core_aes.AesDecryptCtx(Aes128);

pub const Aes = struct {
    pub const block_length = Aes128.block.block_length;

    pub fn encrypt(dst: []u8, src: []const u8, key: [Aes128.block.block_length]u8, iv: [AesEncryptCtx.block_length]u8) void {
        const context = Aes128.initEnc(key);
        cbc(@TypeOf(context), context, dst, src, iv);
    }

    pub fn decrypt(dst: []u8, src: []const u8, key: [Aes128.block.block_length]u8, iv: [AesDecryptCtx.block_length]u8) void {
        const context = Aes128.initEnc(key);
        const decrypt_context = AesDecryptCtx.initFromEnc(context);
        cbc(@TypeOf(decrypt_context), decrypt_context, dst, src, iv);
    }
};

fn cbc(comptime BlockCipher: anytype, block_cipher: BlockCipher, dst: []u8, src: []const u8, iv: [BlockCipher.block_length]u8) void {
    const block_length = BlockCipher.block_length;
    std.debug.assert((src.len % block_length) == 0);
    std.debug.assert(dst.len >= src.len);

    var last: [BlockCipher.block_length]u8 = iv;
    var i: usize = 0;

    while (i + block_length <= src.len) : (i += block_length) {
        const current = dst[i .. i + block_length][0..block_length];
        block_cipher.xor(current, src[i .. i + block_length][0..block_length], last);
        last = current.*;
    }
}
