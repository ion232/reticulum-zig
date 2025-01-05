const std = @import("std");
const rt = @import("reticulum");
const fixtures = @import("fixtures");
const ohsnap = @import("ohsnap");

test {}

test {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var thread_safe_gpa = std.heap.ThreadSafeAllocator{
        .child_allocator = gpa.allocator(),
    };
    const ally = thread_safe_gpa.allocator();
    var f = try abc(ally);
    var c = f.get_node("C").?;

    while (c.api.collect(rt.units.BitRate.default)) |packet| {
        std.debug.print("{any}\n", .{packet});
    }
}

fn abc(ally: std.mem.Allocator) !fixtures.Framework {
    var f = fixtures.Framework.init(ally, .{});
    const names = [_][]const u8{ "A", "B", "C" };

    for (names) |name| {
        try f.add_node(name);
    }

    try f.connect("A", "B");
    try f.connect("C", "B");

    for (names) |name| {
        const n = f.get_node(name).?;
        const endpoint = try f.add_endpoint(name);
        try n.api.announce(&endpoint, name);
        f.clock.advance(200, .ms);
        try f.process();
    }

    return f;
}
