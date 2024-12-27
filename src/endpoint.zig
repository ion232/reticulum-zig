const Identity = @import("src/crypto.zig").Identity;

pub const Builder = struct {};

const Self = @This();

identity: Identity,
direction: Direction,
method: Method,
name: []const u8,

pub fn init(
    identity: Identity,
    direction: Direction,
    method: Method,
    application_name: []const u8,
    // aspects: ?[][]const u8,
) Self {
    return .{
        .identity = identity,
        .direction = direction,
        .method = method,
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
