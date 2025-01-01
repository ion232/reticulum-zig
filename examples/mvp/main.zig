const std = @import("std");
const rt = @import("reticulum");

const Framework = @import("Framework.zig");

pub fn main() !void {
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const thread_safe_gpa = std.heap.ThreadSafeAllocator{ .child_allocator = gpa.allocator() };
    const ally = thread_safe_gpa.allocator();
    const f = Framework.init(ally);
    const names = [_][]const u8{ "A", "B", "C" };

    for (names) |name| {
        _ = try f.add_node(name);
    }

    try f.connect("A", "B");
    try f.connect("C", "B");

    for (names) |name| {
        const n = f.get_node(name).?;
        const e = f.add_endpoint(name).?;
        try n.api.announce(e, name);
        f.clock.advance(200, .ms);
        f.process();
    }

    const c = f.get_node("C").?;

    while (c.api.collect()) |packet| {
        std.debug.print("{any}\n", .{packet});
    }
}
