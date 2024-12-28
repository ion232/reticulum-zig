const std = @import("std");

pub fn main() !void {
    const z = [_][]const u8{ "a", "b" };
    x(&z);
}

fn x(y: []const []const u8) void {
    std.debug.print("{any}", .{y});
}
