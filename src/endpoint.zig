const std = @import("std");
const Identity = @import("crypto.zig").Identity;

const Self = @This();

identity: Identity,
direction: Direction,
method: Method,
application_name: []const u8,
aspects: [][]const u8,

pub fn init(
    identity: Identity,
    direction: Direction,
    method: Method,
    application_name: []const u8,
    aspects: [][]const u8,
) Self {
    return .{
        .identity = identity,
        .direction = direction,
        .method = method,
        .application_name = application_name,
        .aspects = aspects,
    };
}

pub const Direction = enum {
    in,
    out,
};

pub const Method = enum {
    plain,
    single,
    group,
    link,
};
