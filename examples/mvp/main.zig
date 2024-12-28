const std = @import("std");
const reticulum = @import("reticulum");

const Os = reticulum.System.Os;
const Node = reticulum.Node;

pub fn main() !void {
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
