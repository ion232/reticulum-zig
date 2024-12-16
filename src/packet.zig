const std = @import("std");

pub const Packet = struct {
    const Self = @This();

    header: Header,
    ifac: ?[]const u8,
    endpoint: []const u8,
    other_endpoint: ?[]const u8,
    context: u8,
    payload: []const u8,

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

pub const Header = packed struct {
    pub const Flag = struct {
        pub const Ifac = enum(u1) {
            open,
            auth,
        };

        pub const AddressCount = enum(u1) {
            one,
            two,
        };

        pub const Context = enum(u1) {
            off,
            on,
        };

        pub const Propagation = enum(u1) {
            broadcast,
            transport,
        };

        pub const Endpoint = enum(u2) {
            single,
            group,
            plain,
            link,
        };

        pub const Purpose = enum(u2) {
            data,
            announce,
            link_request,
            proof,
        };
    };

    ifac: Flag.Ifac,
    address_count: Flag.AddressCount,
    context: Flag.Context,
    propagation: Flag.Propagation,
    endpoint: Flag.Endpoint,
    purpose: Flag.Purpose,
    hops: u8,
};
