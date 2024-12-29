const std = @import("std");
const endpoint = @import("../endpoint.zig");
const crypto = @import("../crypto.zig");
const packet = @import("../packet.zig");

const Allocator = std.mem.Allocator;
const Bytes = std.ArrayList(u8);
const Header = packet.Header;
const Context = packet.Context;
const Hash = crypto.Hash;

const Self = @This();

ally: Allocator,
header: Header = undefined,
interface_access_code: Bytes,
endpoints: Endpoints = undefined,
context: Context = undefined,
payload: Bytes,

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .interface_access_code = Bytes.init(ally),
        .payload = Bytes.init(ally),
    };
}

pub fn hash(self: *const Self) Hash {
    const header: u8 = std.mem.bytesAsSlice(u4, self.header)[1];

    return switch (self.endpoints) {
        .normal => |normal| Hash.from_items(.{
            .header = header,
            .endpoint = normal.endpoint,
            .context = self.context,
            .payload = self.payload,
        }),
        .transport => |transport| Hash.from_items(.{
            .header = header,
            .transport_id = transport.transport_id,
            .endpoint = transport.endpoint,
            .context = self.context,
            .payload = self.payload,
        }),
    };
}

pub fn size(self: *Self) usize {
    var total_size: usize = 0;

    total_size += @sizeOf(@TypeOf(self.header));
    total_size += self.interface_access_code.items.len;
    total_size += switch (self.endpoints) {
        .normal => |*n| n.endpoint.items.len,
        .transport => |*t| t.transport_id.items.len + t.endpoint.items.len,
    };
    total_size += @sizeOf(@TypeOf(self.context));
    total_size += self.payload.len;

    return total_size;
}

pub const Endpoints = union(packet.Header.Flag.Format) {
    normal: struct {
        endpoint: Bytes,
    },
    transport: struct {
        transport_id: Bytes,
        endpoint: Bytes,
    },
};
