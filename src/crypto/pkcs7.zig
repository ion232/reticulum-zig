const std = @import("std");

pub const UnpadError = error{
    InvalidLength,
    InvalidPadValue,
};

pub fn pad(data: []u8, out: []u8, comptime block_length: u8) []u8 {
    const r: u8 = @intCast(data.items.len % block_length);
    const n = block_length - r;
    std.debug.assert(out.len >= data.len);

    @memcpy(out, data);

    for (0..n) |i| {
        out[data.len + i] = n;
    }

    return out[0 .. data.len + n];
}

pub fn unpad(data: []u8, out: []u8, comptime block_length: u8) ![]u8 {
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

    std.debug.assert(out.len >= data.len - n);

    // Does this need to be copied?
    @memcpy(out, data[0 .. data.len - n]);

    return out[0 .. data.len - n];
}

test "pad - empty" {
    const allocator = std.testing.allocator;
    const block_length = 16;

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    try pad(&data, block_length);
    try std.testing.expectEqual(16, data.items.len);
    try std.testing.expectEqual(16, data.items[0]);
}

test "pad - length 1" {
    const allocator = std.testing.allocator;
    const block_length = 16;

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    try data.append(1);
    try pad(&data, block_length);
    try std.testing.expectEqual(@as(usize, 16), data.items.len);
    try std.testing.expectEqual(@as(u8, 15), data.items[data.items.len - 1]);
}

test "pad - block size" {
    const allocator = std.testing.allocator;
    const block_length = 16;

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    try data.appendNTimes(1, block_length);
    try pad(&data, block_length);
    try std.testing.expectEqual(@as(usize, 32), data.items.len);
    try std.testing.expectEqual(@as(u8, 16), data.items[data.items.len - 1]);
}

test "unpad - valid one block" {
    const allocator = std.testing.allocator;
    const block_length = 16;

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    try data.appendNTimes(4, 16);
    try unpad(&data, block_length);
    try std.testing.expectEqual(@as(usize, 12), data.items.len);
}

test "unpad - valid two blocks" {
    const allocator = std.testing.allocator;
    const block_length = 16;

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();
    try data.appendNTimes(1, 30);
    try data.appendNTimes(2, 2);
    try unpad(&data, block_length);
    try std.testing.expectEqual(@as(usize, 30), data.items.len);
}

// ion232: A value that's too small can't be tested for. I don't think it actually matters though in practice.

test "unpad - value too big" {
    const allocator = std.testing.allocator;
    const block_length = 16;

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();

    try data.appendNTimes(1, 15);
    try data.append(17);

    try std.testing.expectError(UnpadError.InvalidPadValue, unpad(&data, block_length));
}

test "unpad - invalid sum" {
    const allocator = std.testing.allocator;
    const block_length = 16;

    var data = std.ArrayList(u8).init(allocator);
    defer data.deinit();

    try data.appendNTimes(1, 14);
    try data.append(0);
    try data.append(2);

    try std.testing.expectError(UnpadError.InvalidSum, unpad(&data, block_length));
}
