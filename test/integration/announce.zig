const std = @import("std");
const rt = @import("reticulum");
const t = std.testing;

const Framework = @import("Framework.zig");
const Verifier = @import("ohsnap");

test {
    const ally = t.allocator;
    var f = try abc(ally);
    var c = f.getNode("C").?;

    const verifier = Verifier{};

    while (c.api.collect(rt.units.BitRate.default)) |packet| {
        const snapshot = verifier.snap(
            @src(),
            \\{ 123, 234 }
            ,
        );
        try snapshot.expectEqualFmt(packet);
    }
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
