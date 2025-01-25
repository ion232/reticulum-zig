const std = @import("std");
const rt = @import("reticulum");
const t = std.testing;

const Framework = @import("kit/Framework.zig");
const Verifier = @import("ohsnap");
const verifier = Verifier{};

test {
    const ally = t.allocator;
    const topology = .{
        .a = .{
            .interfaces = .{
                .a0 = .{
                    .to = .{.b0},
                },
            },
        },
        .b = .{
            .options = .{
                .transport_enabled = true,
                .transport_identity = null,
                .max_interfaces = 256,
                .max_incoming_packets = 1024,
                .max_outgoing_packets = 1024,
            },
            .interfaces = .{
                .b0 = .{
                    .to = .{.a0},
                },
                .b1 = .{
                    .to = .{.c0},
                },
            },
        },
        .c = .{
            .interfaces = .{
                .c0 = .{
                    .to = .{.b1},
                },
            },
        },
    };

    var f = try Framework.fromTopology(topology, ally);

    try verifier.snap(
        @src(),
        \\{ 123, 234 }
        ,
    ).expectEqualFmt(f.collect("C", "c0"));
}

test {
    // Setup nodes. Don't bother with shared and local instances.
    // Setup topology.
    // Send announces as needed.
    // Check produced packets.
    // Send other packets.
    // Check produced packets.
}

test {
    // A-B-C.
    // B is transport node.
    // A and C are not.
    // Announce at C gets to A.
    // Message from A can get to C.

}

fn abc(ally: std.mem.Allocator) !Framework {
    var f = Framework.init(ally, .{});
    const names = [_][]const u8{ "A", "B", "C" };

    for (names) |name| {
        try f.addNode(name);
    }

    try f.connect("A", "B");
    try f.connect("C", "B");

    for (names) |name| {
        const n = f.getNode(name).?;
        const endpoint = try f.addEndpoint(name);
        try n.api.announce(&endpoint, name);
        f.clock.advance(200, .ms);
        try f.process();
    }

    return f;
}
