const std = @import("std");
const endpoint = @import("../endpoint.zig");
const crypto = @import("../crypto.zig");
const Hash = crypto.Hash;

pub const Packet = struct {
    const Self = @This();

    header: Header,
    endpoints: Endpoints,
    context: Context,
    payload: []const u8,

    pub fn hash(self: *const Self) Hash {
        const header_bits: u8 = std.mem.bytesAsSlice(u4, self.header)[1];

        return switch (self.endpoints) {
            .normal => |normal| Hash.from_items(.{
                .header_bits = header_bits,
                .endpoint = normal.endpoint,
                .context = self.context,
                .payload = self.payload,
            }),
            .transport => |transport| Hash.from_items(.{
                .header_bits = header_bits,
                .transport_id = transport.transport_id,
                .endpoint = transport.endpoint,
                .context = self.context,
                .payload = self.payload,
            }),
        };
    }

    pub fn parse(bytes: []const u8) !Packet {
        const header_size = @sizeOf(Header);
        const header: Header = @bitCast(bytes[0..header_size]);

        return .{
            .header = header,
        };
    }

    pub fn write(self: *Self, buffer: []u8) !void {
        if (buffer.len < self.size()) {
            return;
        }

        var i = 0;

        const header_size = @sizeOf(@TypeOf(self.header));
        @memcpy(buffer[i .. i + header_size], &self.header);
        i += header_size;

        if (self.ifac != null) {
            @memcpy(buffer[i .. i + self.ifac.?.len], self.ifac.?);
            i += self.ifac.?.len;
        }

        @memcpy(buffer[i .. i + self.endpoint.len], self.endpoint);
        i += self.endpoint.len;

        if (self.other_endpoint != null) {
            @memcpy(buffer[i .. i + self.other_endpoint.?.len], self.other_endpoint.?);
            i += self.other_endpoint.?.len;
        }

        const context_size = @sizeOf(@TypeOf(self.context));
        @memcpy(buffer[i .. i + context_size], &self.context);
        i += context_size;

        @memcpy(buffer[i .. i + self.payload.len], self.payload);
    }

    pub fn size(self: *Self) usize {
        var total_size = 0;

        total_size += @sizeOf(@TypeOf(self.header));

        if (self.ifac != null) {
            total_size += self.ifac.?.len;
        }

        total_size += self.endpoint.len;

        if (self.other_endpoint != null) {
            total_size += self.other_endpoint.?.len;
        }

        total_size += @sizeOf(@TypeOf(self.context));
        total_size += self.payload.len;

        return total_size;
    }
};
