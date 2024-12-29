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
interface_access_code: []const u8,
endpoints: Endpoints = undefined,
context: Context = undefined,
payload: []const u8,

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .interface_access_code = &[_]u8{},
        .payload = &[_]u8{},
    };
}

pub const Endpoints = union(packet.Header.Flag.Format) {
    normal: struct {
        endpoint: []const u8,
    },
    transport: struct {
        transport_id: []const u8,
        endpoint: []const u8,
    },
};
