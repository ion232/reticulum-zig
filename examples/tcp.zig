const std = @import("std");
const core = @import("core");
const io = @import("io");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const ally = gpa.allocator();
    var clock = try io.os.Clock.init();
    var rng = io.os.Rng.init();
    var system = core.System{
        .clock = clock.clock(),
        .rng = rng.rng(),
    };

    var node = try core.Node.init(ally, &system, null, .{});
    const host = "amsterdam.connect.reticulum.network";
    const port = 4965;

    var driver = try io.driver.Tcp.init(&node, host, port, ally);
    defer driver.deinit();

    try driver.run();
}
