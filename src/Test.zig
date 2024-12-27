const std = @import("std");

const Os = @import("System.zig").Os;
const Node = @import("Node.zig");

test "Proof of concept" {
    const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    const os = try Os.init();
    const system = os.system();

    const node = Node.init(ally, system, .{});
    const interface_id = try node.addInterface(.{});
    try node.push(interface_id, .{});
    try node.process();
    const raw_data = try node.pop(interface_id);
    std.debug.print("{any}\n", .{raw_data});
}
