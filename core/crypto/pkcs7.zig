const std = @import("std");

pub fn Pkcs7(comptime block_size: u8) type {
    return struct {
        pub const Error = error{
            InvalidLength,
            InvalidPadValue,
        };

        const block_length = block_size;

        pub fn pad(data: []const u8, buffer: []u8) []u8 {
            std.debug.assert(buffer.len >= block_length);

            const r: u8 = @intCast(data.len % block_length);
            const n = block_length - r;

            for (0..n) |i| {
                buffer[data.len + i] = n;
            }

            return buffer[0 .. data.len + n];
        }

        pub fn unpad(blocks: []const u8) Error![]const u8 {
            if (blocks.len < block_length or (blocks.len % block_length) != 0) {
                return Error.InvalidLength;
            }

            const last_block = blocks[blocks.len - block_length .. blocks.len];
            const n = last_block[last_block.len - 1];

            if (n == 0 or n > block_length) {
                return Error.InvalidPadValue;
            }

            for (0..n) |i| {
                if (n != last_block[last_block.len - i - 1]) {
                    return Error.InvalidPadValue;
                }
            }

            return blocks[0 .. blocks.len - n];
        }
    };
}

const t = std.testing;
const P = Pkcs7(16);

test "pad - empty" {
    const data: [0]u8 = undefined;
    var out: [P.block_length]u8 = undefined;

    const padded = P.pad(&data, &out);
    try t.expectEqual(P.block_length, padded.len);
    try t.expectEqual(P.block_length, padded[0]);
}

test "pad - length 1" {
    var data: [1]u8 = undefined;
    var out: [P.block_length]u8 = undefined;

    data[0] = 1;

    const padded = P.pad(&data, &out);
    try t.expectEqual(@as(usize, P.block_length), padded.len);
    try t.expectEqual(@as(u8, P.block_length - 1), padded[padded.len - 1]);
}

test "pad - block size" {
    var data: [P.block_length]u8 = undefined;
    var out: [2 * P.block_length]u8 = undefined;

    @memset(data[0..P.block_length], 1);

    const padded = P.pad(&data, &out);
    try t.expectEqual(@as(usize, 2 * P.block_length), padded.len);
    try t.expectEqual(@as(u8, P.block_length), padded[padded.len - 1]);
}

test "unpad - one valid block" {
    var data: [P.block_length]u8 = undefined;
    @memset(data[0..P.block_length], 4);

    const unpadded = try P.unpad(&data);
    try t.expectEqual(@as(usize, P.block_length - 4), unpadded.len);
}

test "unpad - two valid blocks" {
    const real_data_length = (2 * P.block_length) - 2;

    var data: [2 * P.block_length]u8 = undefined;

    @memset(data[0..real_data_length], 1);
    @memset(data[real_data_length .. real_data_length + 2], 2);

    const unpadded = try P.unpad(&data);
    try t.expectEqual(@as(usize, real_data_length), unpadded.len);
}

test "unpad - data plus full padding block" {
    var data: [2 * P.block_length]u8 = undefined;
    @memset(data[P.block_length .. 2 * P.block_length], P.block_length);

    const unpadded = try P.unpad(&data);
    try t.expectEqual(P.block_length, unpadded.len);
}

test "unpad - just padding block" {
    var data: [P.block_length]u8 = undefined;
    @memset(data[0..P.block_length], P.block_length);

    const unpadded = try P.unpad(&data);
    try t.expectEqual(0, unpadded.len);
}

// A value that's too small can't be tested for. I don't think it actually matters though in practice.

test "unpad - value too big" {
    var data: [P.block_length]u8 = undefined;

    @memset(data[0 .. P.block_length - 1], 1);
    data[P.block_length - 1] = P.block_length + 1;

    const unpadded = P.unpad(&data);
    try t.expectError(P.Error.InvalidPadValue, unpadded);
}

test "unpad - invalid values" {
    var data: [P.block_length]u8 = undefined;

    @memset(data[0 .. P.block_length - 2], 1);
    data[P.block_length - 2] = 0;
    data[P.block_length - 1] = 2;

    const unpadded = P.unpad(&data);
    try t.expectError(P.Error.InvalidPadValue, unpadded);
}
