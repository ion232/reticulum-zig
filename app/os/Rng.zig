const std = @import("std");
const Rng = @import("../../System.zig").Rng;

const Self = @This();

pub fn init() Self {
    return .{};
}

pub fn rng(self: *Self) Rng {
    _ = self;
    return std.crypto.random;
}
