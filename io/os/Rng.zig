const core = @import("core");
const std = @import("std");

const Self = @This();

pub fn init() Self {
    return .{};
}

pub fn rng(self: *Self) core.System.Rng {
    _ = self;
    return std.crypto.random;
}
