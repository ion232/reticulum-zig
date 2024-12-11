const std = @import("std");

pub const UnpadError = error{
    InvalidLength,
    InvalidPadValue,
};

// Wrap this in a comptime struct.

pub fn pad(comptime block_length: u8, data: []const u8, out: []u8) []u8 {
    const r: u8 = @intCast(data.len % block_length);
    const n = block_length - r;
    std.debug.assert(out.len >= data.len);

    @memcpy(out[0..data.len], data[0..data.len]);

    for (0..n) |i| {
        out[data.len + i] = n;
    }

    return out[0 .. data.len + n];
}

pub fn unpad(comptime block_length: u8, data: []const u8) ![]const u8 {
    if (data.len == 0 or (data.len % block_length) != 0) {
        return UnpadError.InvalidLength;
    }

    const n = data[data.len - 1];
    if (n == 0 or n >= block_length or n > data.len) {
        return UnpadError.InvalidPadValue;
    }

    for (0..n) |i| {
        if (n != data[data.len - i - 1]) {
            return UnpadError.InvalidPadValue;
        }
    }

    return data[0 .. data.len - n];
}

const t = std.testing;

test "pad - empty" {
    const block_length = 16;

    const data: [0]u8 = undefined;
    var out: [block_length]u8 = undefined;

    const padded = pad(block_length, &data, &out);
    try t.expectEqual(block_length, padded.len);
    try t.expectEqual(block_length, padded[0]);
}

test "pad - length 1" {
    const block_length = 16;

    var data: [1]u8 = undefined;
    var out: [block_length]u8 = undefined;

    data[0] = 1;

    const padded = pad(block_length, &data, &out);
    try t.expectEqual(@as(usize, block_length), padded.len);
    try t.expectEqual(@as(u8, block_length - 1), padded[padded.len - 1]);
}

test "pad - block size" {
    const block_length = 16;

    var data: [block_length]u8 = undefined;
    var out: [2 * block_length]u8 = undefined;

    @memset(data[0..block_length], 1);

    const padded = pad(block_length, &data, &out);
    try t.expectEqual(@as(usize, 2 * block_length), padded.len);
    try t.expectEqual(@as(u8, block_length), padded[padded.len - 1]);
}

test "unpad - valid one block" {
    const block_length = 16;

    var data: [block_length]u8 = undefined;
    @memset(data[0..block_length], 4);

    const unpadded = try unpad(block_length, &data);
    try t.expectEqual(@as(usize, block_length - 4), unpadded.len);
}

test "unpad - valid two blocks" {
    const block_length = 16;
    const real_data_length = 2 * (block_length - 1);

    var data: [2 * block_length]u8 = undefined;

    @memset(data[0..real_data_length], 1);
    @memset(data[real_data_length .. real_data_length + 2], 2);

    const unpadded = try unpad(block_length, &data);
    try t.expectEqual(@as(usize, real_data_length), unpadded.len);
}

// ion232: A value that's too small can't be tested for. I don't think it actually matters though in practice.

test "unpad - value too big" {
    const block_length = 16;

    var data: [block_length]u8 = undefined;

    @memset(data[0 .. block_length - 1], 1);
    data[block_length - 1] = block_length + 1;

    const unpadded = unpad(block_length, &data);
    try t.expectError(UnpadError.InvalidPadValue, unpadded);
}

test "unpad - invalid values" {
    const block_length = 16;

    var data: [block_length]u8 = undefined;

    @memset(data[0 .. block_length - 2], 1);
    data[block_length - 2] = 0;
    data[block_length - 1] = 2;

    const unpadded = unpad(block_length, &data);
    try t.expectError(UnpadError.InvalidPadValue, unpadded);
}
