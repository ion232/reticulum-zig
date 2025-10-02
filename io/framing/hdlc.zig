const std = @import("std");

const Allocator = std.mem.Allocator;

const flag = 0x7e;
const escape = 0x7d;
const escape_mask = 0x20;
const escaped_escape = 0x5d;
const escaped_flag = 0x5e;

pub const Writer = struct {
    writer: *std.Io.Writer,

    const Self = @This();

    pub fn init(writer: *std.Io.Writer) Self {
        return .{
            .writer = writer,
        };
    }

    pub fn writeFrame(self: Self, payload: []const u8) !void {
        try self.writer.writeByte(flag);

        var start: usize = 0;
        var index: usize = 0;

        while (index < payload.len) : (index += 1) {
            const byte = payload[index];

            if (byte == escape or byte == flag) {
                if (index > start) {
                    try self.writer.writeAll(payload[start..index]);
                }

                try self.writer.writeByte(escape);
                try self.writer.writeByte(byte ^ escape_mask);

                start = index + 1;
            }
        }

        if (start < payload.len) {
            try self.writer.writeAll(payload[start..]);
        }

        try self.writer.writeByte(flag);
    }
};

pub const Reader = struct {
    const Self = @This();

    reader: *std.Io.Reader,

    pub fn init(reader: *std.Io.Reader) Self {
        return .{
            .reader = reader,
        };
    }

    // I'm assuming here that a valid frame can always be read in one call.
    pub fn readFrame(self: *Self, frame: []u8) !usize {
        var index: usize = 0;
        var escaped = false;

        while (true) {
            if (index >= frame.len) return error.FrameFull;

            switch (try self.reader.takeByte()) {
                flag => break,
                escape => escaped = true,
                else => |byte| {
                    if (escaped) {
                        frame[index] = byte ^ escape_mask;
                        escaped = false;
                    } else {
                        frame[index] = byte;
                    }

                    index += 1;
                },
            }
        }

        return index;
    }
};

const t = std.testing;

test "write" {
    var io_writer = std.Io.Writer.Allocating.init(t.allocator);
    defer io_writer.deinit();

    const writer = Writer.init(&io_writer.writer);

    const input = "this is some data";
    try writer.writeFrame(input);
    try t.expectEqualSlices(u8, [_]u8{flag} ++ input ++ [_]u8{flag}, io_writer.written());
    io_writer.clearRetainingCapacity();

    const flag_input = [_]u8{flag};
    try writer.writeFrame(&flag_input);
    try t.expectEqualSlices(u8, &[_]u8{ flag, escape, escaped_flag, flag }, io_writer.written());
    io_writer.clearRetainingCapacity();

    const esc_input = [_]u8{escape};
    const escaped_esc = [_]u8{ flag, escape, escaped_escape, flag };
    try writer.writeFrame(&esc_input);
    try t.expectEqualSlices(u8, &escaped_esc, io_writer.written());
    io_writer.clearRetainingCapacity();

    const mixed_input = [_]u8{ 0x01, flag, 0x02, escape, 0x03, 0x04, escape_mask };
    const mixed_expected = [_]u8{ flag, 0x01, escape, escaped_flag, 0x02, escape, escaped_escape, 0x03, 0x04, escape_mask, flag };
    try writer.writeFrame(&mixed_input);
    try t.expectEqualSlices(u8, &mixed_expected, io_writer.written());
    io_writer.clearRetainingCapacity();
}

test "read" {
    const payload = "this is some data";
    var io_reader = std.Io.Reader.fixed([_]u8{flag} ++ payload ++ [_]u8{flag});
    var reader = Reader.init(&io_reader);
    var frame: [32]u8 = @splat(0);

    var n = try reader.readFrame(&frame);
    try t.expectEqual(0, n);

    n = try reader.readFrame(&frame);
    try t.expectEqualSlices(u8, payload, frame[0..n]);

    const err = reader.readFrame(&frame);
    try t.expectError(error.EndOfStream, err);
}

test "read-multiple-flags" {
    var io_reader = std.Io.Reader.fixed(&[_]u8{ flag, 0x01, 0x02, flag, 0x03, 0x04, flag });
    var reader = Reader.init(&io_reader);
    var frame: [32]u8 = @splat(0);

    var n = try reader.readFrame(&frame);
    try t.expectEqual(0, n);

    n = try reader.readFrame(&frame);
    try t.expectEqualSlices(u8, &[_]u8{ 0x01, 0x02 }, frame[0..n]);

    n = try reader.readFrame(&frame);
    try t.expectEqualSlices(u8, &[_]u8{ 0x03, 0x04 }, frame[0..n]);

    const err = reader.readFrame(&frame);
    try t.expectError(error.EndOfStream, err);
}

test "read-mixed-data" {
    var io_reader = std.Io.Reader.fixed(
        &[_]u8{ flag, 0x01, escape, escaped_flag, 0x02, escape, escaped_escape, 0x03, flag },
    );
    var reader = Reader.init(&io_reader);
    var frame: [32]u8 = @splat(0);

    var n = try reader.readFrame(&frame);
    try t.expectEqual(0, n);

    n = try reader.readFrame(&frame);
    const unescaped = [_]u8{ 0x01, flag, 0x02, escape, 0x03 };
    try t.expectEqualSlices(u8, &unescaped, frame[0..n]);

    const err = reader.readFrame(&frame);
    try t.expectError(error.EndOfStream, err);
}

test "round-trip" {
    var io_writer = std.Io.Writer.Allocating.init(t.allocator);
    defer io_writer.deinit();

    const input = [_]u8{ 0x00, flag, 0xaa, escape, 0xff, flag, escape };
    const writer = Writer.init(&io_writer.writer);
    try writer.writeFrame(&input);

    const escaped = [_]u8{ flag, 0x00, escape, escaped_flag, 0xaa, escape, escaped_escape, 0xff, escape, escaped_flag, escape, escaped_escape, flag };
    try t.expectEqualSlices(u8, &escaped, io_writer.written());

    var io_reader = std.Io.Reader.fixed(io_writer.written());
    var reader = Reader.init(&io_reader);
    var frame: [32]u8 = @splat(0);

    var n = try reader.readFrame(&frame);
    try t.expectEqual(0, n);

    n = try reader.readFrame(&frame);
    try t.expectEqualSlices(u8, &input, frame[0..n]);
}
