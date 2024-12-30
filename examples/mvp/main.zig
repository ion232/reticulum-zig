const std = @import("std");
const rt = @import("reticulum");

pub fn main() !void {
    std.debug.print("We're compiled and running - that's good news!", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = std.heap.ThreadSafeAllocator{ .child_allocator = gpa.allocator() };
    var os = try rt.System.Os.init();
    var system = os.system();

    const node = try rt.Node.init(ally, system, .{});
    const api = try node.addInterface(.{});

    const endpoint_in = try rt.endpoint.Builder.init(ally)
        .set_identity(rt.crypto.Identity.random(&system.rng))
        .set_direction(.in)
        .set_method(.single)
        .set_application_name("mvp")
        .append_aspect("echo")
        .build();
    const endpoint_out = try rt.endpoint.Builder.init(ally)
        .set_identity(endpoint_in.identity)
        .set_direction(.out)
        .set_method(.single)
        .set_application_name("mvp")
        .append_aspect("echo")
        .build();

    {
        api.announce(&endpoint_in, "some-application-data");
        try node.process();
    }

    {
        const packet = rt.packet.Builder.init(ally)
            .set_header(.{})
            .set_endpoint(endpoint_out.hash)
            .append_payload("this-is-a-payload")
            .build();
        api.send(packet);
        try node.process();
    }

    while (api.collect()) |packet| {
        std.debug.print("{any}", .{packet});
    }
}
