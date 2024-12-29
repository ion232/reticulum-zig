const std = @import("std");
const rt = @import("reticulum");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = std.heap.ThreadSafeAllocator{ .child_allocator = gpa.allocator() };
    var os = try rt.System.Os.init();
    var system = os.system();
    const node = try rt.Node.init(ally, system, .{});

    const identity = rt.crypto.Identity.random(&system.rng);
    const endpoint = try rt.endpoint.Builder.init(ally)
        .set_identity(identity)
        .set_direction(.in)
        .set_method(.single)
        .set_application_name("mvp-example")
        .append_aspect("one")
        .build();
    const announce = rt.packet.announce(endpoint);

    const interface_id = try node.addInterface(.{});
    try node.push(interface_id, .{announce});
    try node.process();
    const raw_data = try node.pop(interface_id);
    std.debug.print("{any}\n", .{raw_data});
}

// Push outgoing packet(s) into a per interface intermediary structure for storing outgoing packets.
// Each interface is running in its own thread.
// Each interface queries its structure for ready outgoing packets, including announces.
// The interface also does the work of processing incoming packets, etc, on its thread when it queries.
// Otherwise the node would have to do the work of N interfaces. This is classic separation of concerns.
// The interface then gets the data and sends it.
// The store will handle authentication through the access code, announces, etc.
// The store will also handle
