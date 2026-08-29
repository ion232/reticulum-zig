const std = @import("std");

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
