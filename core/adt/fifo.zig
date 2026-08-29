/// Modified from kobolds-io/stdx RingBuffer.
const std = @import("std");
const t = std.testing;

const Allocator = std.mem.Allocator;

/// Fixed sized fifo.
pub fn Fifo(comptime T: type) type {
    return struct {
        pub const Error = error{Full};

        const Self = @This();

        buffer: []T,
        head: usize,
        tail: usize,
        count: usize,

        // TODO: Use bit shift when capacity is a power of two.
        pub fn init(allocator: Allocator, capacity: usize) !Self {
            const buffer = try allocator.alloc(T, capacity);

            return Self{
                .buffer = buffer,
                .head = 0,
                .tail = 0,
                .count = 0,
            };
        }

        pub fn remaining(self: *Self) usize {
            return self.buffer.len - self.count;
        }

        pub fn push(self: *Self, value: T) Error!void {
            if (self.isFull()) return Error.Full;

            self.buffer[self.tail] = value;
            self.tail = (self.tail + 1) % self.buffer.len;
            self.count += 1;
        }

        pub fn pop(self: *Self) ?T {
            if (self.isEmpty()) return null;

            const value = self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
            self.count -= 1;

            return value;
        }

        pub fn copyTo(self: *Self, other: *Self) !void {
            if (self.remaining() < other.count) return Error.Full;

            var i: usize = 0;
            while (i < other.count) : (i += 1) {
                const index = (other.head + i) % other.buffer.len;
                self.buffer[self.tail] = other.buffer[index];
                self.tail = (self.tail + 1) % self.buffer.len;
            }

            self.count += other.count;
        }

        pub fn isEmpty(self: *Self) bool {
            return self.remaining() == self.buffer.len;
        }

        pub fn isFull(self: *Self) bool {
            return self.remaining() == 0;
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.buffer);
        }
    };
}

test "push" {
    var fifo = try Fifo(u8).init(t.allocator, 10);
    defer fifo.deinit(t.allocator);

    try t.expectEqual(0, fifo.count);

    const test_value: u8 = 231;
    try fifo.push(test_value);
    try t.expectEqual(1, fifo.count);

    for (0..9) |_| {
        try fifo.push(test_value);
    }

    try t.expectEqual(true, fifo.isFull());
    try t.expectError(error.Full, fifo.push(test_value));
}

test "pop" {
    var fifo = try Fifo(u8).init(t.allocator, 10);
    defer fifo.deinit(t.allocator);

    const test_value: u8 = 231;

    for (0..10) |_| {
        try fifo.push(test_value);
    }

    try t.expectEqual(true, fifo.isFull());

    var removed: usize = fifo.buffer.len;

    while (fifo.pop()) |v| : (removed -= 1) {
        try t.expectEqual(test_value, v);
    }

    try t.expectEqual(true, fifo.isEmpty());
}

test "copy" {
    var src = try Fifo(u8).init(t.allocator, 10);
    defer src.deinit(t.allocator);

    var dest = try Fifo(u8).init(t.allocator, 20);
    defer dest.deinit(t.allocator);

    const values: [5]u8 = .{ 10, 20, 30, 40, 50 };
    for (values) |v| {
        try src.push(v);
    }

    try t.expectEqual(@as(usize, values.len), src.count);
    try t.expectEqual(true, dest.isEmpty());

    try dest.copyTo(&src);
    try t.expectEqual(@as(usize, values.len), src.count);

    for (values) |expected| {
        const actual = src.pop().?;
        try t.expectEqual(expected, actual);
    }

    for (values) |v| {
        try src.push(v);
    }

    for (values) |expected| {
        const actual = dest.pop().?;
        try t.expectEqual(expected, actual);
    }

    try t.expectEqual(true, dest.isEmpty());
    try t.expectEqual(@as(usize, values.len), src.count);
}

test "copy-invalid" {
    var src = try Fifo(u8).init(t.allocator, 5);
    defer src.deinit(t.allocator);

    var dest = try Fifo(u8).init(t.allocator, 3);
    defer dest.deinit(t.allocator);

    for (0..5) |_| {
        try src.push(7);
    }

    try t.expectError(error.Full, dest.copyTo(&src));
    try t.expectEqual(true, dest.isEmpty());
}
