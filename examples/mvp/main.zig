const std = @import("std");
const rt = @import("reticulum");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();
    var os = try rt.System.Os.init();

    const node = try rt.Node.init(ally, os.system(), .{});
    const interface_id = try node.addInterface(.{});
    try node.push(interface_id, .{});
    try node.process();
    const raw_data = try node.pop(interface_id);
    std.debug.print("{any}\n", .{raw_data});
}
