const std = @import("std");
const rt = @import("reticulum");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = std.heap.ThreadSafeAllocator{ .child_allocator = gpa.allocator() };
    var os = try rt.System.Os.init();
    var system = os.system();

    const identity = rt.crypto.Identity.random(&system.rng);
    const endpoint = try rt.endpoint.Builder.init(ally)
        .set_identity(identity)
        .set_direction(.in)
        .set_method(.single)
        .set_application_name("mvp-example")
        .add_aspect("one")
        .build();
    const packet = rt.packet.Builder(ally)
        .to_endpoint(endpoint)
        .build();

    const node = try rt.Node.init(ally, system, .{});

    const interface_id = try node.addInterface(.{});
    try node.push(interface_id, .{});
    try node.process();
    const raw_data = try node.pop(interface_id);
    std.debug.print("{any}\n", .{raw_data});
}
