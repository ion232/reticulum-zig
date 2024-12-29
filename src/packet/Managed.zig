const std = @import("std");
const endpoint = @import("../endpoint.zig");
const crypto = @import("../crypto.zig");
const packet = @import("../packet.zig");

const Allocator = std.mem.Allocator;
const Bytes = @import("../internal/Bytes.zig");
const Header = packet.Header;
const Context = packet.Context;

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

pub const Endpoints = union(packet.Header.Flag.Format) {
    normal: struct {
        endpoint: Bytes,
    },
    transport: struct {
        transport_id: Bytes,
        endpoint: Bytes,
    },
};
