const std = @import("std");

const Os = @import("system/Os.zig");

pub fn main() !void {
    const os = try Os.init();
    const system = os.system();
}
