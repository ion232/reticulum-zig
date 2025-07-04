const std = @import("std");
const rt = @import("reticulum");
const t = std.testing;
const topology = @import("kit/topology.zig");

const Golden = @import("ohsnap");
const Simulator = @import("kit/Simulator.zig");

test "abc" {
    const golden = Golden{};
    const ally = t.allocator;
    var s = try Simulator.fromTopology(topology.abc, ally);

    defer {
        s.deinit();
    }

    const a0 = s.getInterface("a0").?;
    const b0 = s.getInterface("b0").?;
    const b1 = s.getInterface("b1").?;
    const c0 = s.getInterface("c0").?;

    const name = try rt.endpoint.Name.init(
        "plain",
        &.{ "test", "endpoint" },
        ally,
    );
    const payload = rt.packet.Payload.makeRaw(try rt.data.makeBytes(
        "this is some payload data",
        ally,
    ));

    try a0.api.plain(name, payload);
    try s.step();

    try t.expect(a0.event_buffer.items.len == 1);

    inline for (&.{ b0, b1, c0 }) |n| {
        try t.expect(n.event_buffer.items.len == 0);
    }

    const plain_packet = a0.event_buffer.items[0];

    try golden.snap(
        @src(),
        \\.packet = .{
        \\  .header = .{.open, .normal, .none, .broadcast, .plain, .data, hops(0)},
        \\  .endpoints = .normal{358602dccbe1449748d6ef6b0c1b0471},
        \\  .context = .none,
        \\  .payload = .raw{7468697320697320736f6d65207061796c6f61642064617461},
        \\}
        ,
    ).expectEqualFmt(plain_packet);
}
