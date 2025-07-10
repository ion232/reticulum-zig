const std = @import("std");

const Allocator = std.mem.Allocator;

const flag = 0x7e;
const escape = 0x7d;
const escape_mask = 0x20;
const escaped_escape = 0x5d;
const escaped_flag = 0x5e;

pub fn Writer(comptime W: type) type {
    return struct {
        impl: W,

        const Self = @This();

        pub const Error = W.Error;

        pub fn init(impl: W) Self {
            return .{
                .impl = impl,
            };
        }

        pub fn writeFrame(self: Self, bytes: []const u8) Error!usize {
            try self.impl.writeByte(flag);

            var start: usize = 0;
            var index: usize = 0;

            while (index < bytes.len) : (index += 1) {
                const byte = bytes[index];

                if (byte == escape or byte == flag) {
                    if (index > start) {
                        try self.impl.writeAll(bytes[start..index]);
                    }

                    try self.impl.writeByte(escape);
                    try self.impl.writeByte(byte ^ escape_mask);

                    start = index + 1;
                }
            }

            if (start < bytes.len) {
                try self.impl.writeAll(bytes[start..]);
            }

            try self.impl.writeByte(flag);

            return bytes.len;
        }
    };
}

pub fn Reader(comptime R: type, comptime size: usize) type {
    return struct {
        const Self = @This();

        pub const Error = R.Error || error{EndOfStream};

        impl: R,
        escaped: bool = false,
        buffer: []u8,
        count: usize = 0,
        ally: Allocator,

        pub fn init(impl: R, ally: Allocator) !Self {
            return .{
                .impl = impl,
                .ally = ally,
                .buffer = try ally.alloc(u8, size),
            };
        }

        pub fn deinit(self: *Self) void {
            self.ally.free(self.buffer);
        }

        pub fn readFrames(self: *Self, frame_buffer: [][]const u8) Error!usize {
            const n = self.impl.read(self.buffer[self.count..]) catch |err| {
                if (err == error.EndOfStream and self.count == 0) {
                    return 0;
                }
                return err;
            };

            self.count += n;

            var frame_count: usize = 0;
            var input_index: usize = 0;
            var data_index: usize = 0;

            while (frame_count < frame_buffer.len and input_index < self.count) {
                const frame_start = data_index;

                while (input_index < self.count and data_index < self.buffer.len) {
                    const byte = self.buffer[input_index];
                    input_index += 1;

                    if (self.escaped) {
                        self.buffer[data_index] = byte ^ escape_mask;
                        data_index += 1;
                        self.escaped = false;
                        continue;
                    }

                    switch (byte) {
                        flag => {
                            if (data_index > frame_start) {
                                frame_buffer[frame_count] = self.buffer[frame_start..data_index];
                                frame_count += 1;
                            }
                            break;
                        },
                        escape => {
                            self.escaped = true;
                        },
                        else => {
                            self.buffer[data_index] = byte;
                            data_index += 1;
                        },
                    }
                }
            }

            if (input_index < self.count) {
                const remaining = self.buffer[input_index..self.count];
                std.mem.copyForwards(u8, self.buffer[0..remaining.len], remaining);
                self.count = remaining.len;
            } else {
                self.count = 0;
            }

            return frame_count;
        }
    };
}

const t = std.testing;

test "write" {
    var frames = std.ArrayList(u8).init(t.allocator);
    defer frames.deinit();

    const frames_writer = frames.writer();
    const writer = Writer(@TypeOf(frames_writer)).init(frames_writer);

    const input = "this is some data";
    _ = try writer.writeFrame(input);
    try t.expectEqualSlices(u8, [_]u8{flag} ++ input ++ [_]u8{flag}, frames.items);
    frames.clearRetainingCapacity();

    const flag_input = [_]u8{flag};
    _ = try writer.writeFrame(&flag_input);
    try t.expectEqualSlices(u8, &[_]u8{ flag, escape, escaped_flag, flag }, frames.items);
    frames.clearRetainingCapacity();

    const esc_input = [_]u8{escape};
    const escaped_esc = [_]u8{ flag, escape, escaped_escape, flag };
    _ = try writer.writeFrame(&esc_input);
    try t.expectEqualSlices(u8, &escaped_esc, frames.items);
    frames.clearRetainingCapacity();

    const mixed_input = [_]u8{ 0x01, flag, 0x02, escape, 0x03, 0x04, escape_mask };
    const mixed_expected = [_]u8{ flag, 0x01, escape, escaped_flag, 0x02, escape, escaped_escape, 0x03, 0x04, escape_mask, flag };
    _ = try writer.writeFrame(&mixed_input);
    try t.expectEqualSlices(u8, &mixed_expected, frames.items);
}

test "read" {
    const input = [_]u8{flag} ++ "this is some data" ++ [_]u8{flag};
    var stream = std.io.fixedBufferStream(input);
    var reader = try Reader(
        @TypeOf(stream.reader()),
        input.len,
    ).init(stream.reader(), t.allocator);
    defer reader.deinit();

    var frame_buffer: [1][]const u8 = undefined;
    const n = try reader.readFrames(&frame_buffer);

    try t.expectEqual(frame_buffer.len, n);
    try t.expectEqualSlices(u8, "this is some data", frame_buffer[0]);
}

test "read-multiple-flags" {
    const input = [_]u8{ flag, 0x01, 0x02, flag, 0x03, 0x04, flag };
    var stream = std.io.fixedBufferStream(&input);
    var reader = try Reader(
        @TypeOf(stream.reader()),
        input.len,
    ).init(stream.reader(), t.allocator);
    defer reader.deinit();

    var frame_buffer: [2][]const u8 = undefined;
    const n = try reader.readFrames(&frame_buffer);

    try t.expectEqual(frame_buffer.len, n);
    try t.expectEqualSlices(u8, &[_]u8{ 0x01, 0x02 }, frame_buffer[0]);
    try t.expectEqualSlices(u8, &[_]u8{ 0x03, 0x04 }, frame_buffer[1]);
}

test "read-mixed-data" {
    const input = [_]u8{ flag, 0x01, escape, escaped_flag, 0x02, escape, escaped_escape, 0x03, flag };
    var stream = std.io.fixedBufferStream(&input);
    var reader = try Reader(
        @TypeOf(stream.reader()),
        input.len,
    ).init(stream.reader(), t.allocator);
    defer reader.deinit();

    var frame_buffer: [1][]const u8 = undefined;
    const n = try reader.readFrames(&frame_buffer);

    const unescaped = [_]u8{ 0x01, flag, 0x02, escape, 0x03 };
    try t.expectEqual(frame_buffer.len, n);
    try t.expectEqualSlices(u8, &unescaped, frame_buffer[0]);
}

test "round-trip" {
    var frames = std.ArrayList(u8).init(t.allocator);
    defer frames.deinit();

    const frames_writer = frames.writer();
    const writer = Writer(@TypeOf(frames_writer)).init(frames_writer);

    const input = [_]u8{ 0x00, flag, 0xaa, escape, 0xff, flag, escape };
    _ = try writer.writeFrame(&input);

    var stream = std.io.fixedBufferStream(frames.items);
    var reader = try Reader(
        @TypeOf(stream.reader()),
        input.len * 2,
    ).init(stream.reader(), t.allocator);
    defer reader.deinit();

    var frame_buffer: [1][]const u8 = undefined;
    const n = try reader.readFrames(&frame_buffer);

    try t.expectEqual(frame_buffer.len, n);
    try t.expectEqualSlices(u8, &input, frame_buffer[0]);
}
