const core = @import("core");
const std = @import("std");
const t = std.testing;
const topology = @import("kit/topology.zig");

const ManualClock = @import("kit/ManualClock.zig");
const SeededRng = @import("kit/SeededRng.zig");
const Simulator = @import("kit/Simulator.zig");
const Golden = @import("golden");

test "abc" {
    const golden = Golden{};
    const seed = 42;
    const ally = t.allocator;

    var manual_clock = ManualClock.init();
    var seeded_rng = SeededRng.init(seed);
    var system = core.System{
        .clock = manual_clock.clock(),
        .rng = seeded_rng.rng(),
    };

    var s = try Simulator.fromTopology(topology.abc, &system, ally);
    defer s.deinit();

    const a = s.getNode("a").?;
    const b = s.getNode("b").?;
    const a0 = s.getInterface("a0").?;
    const b0 = s.getInterface("b0").?;
    const b1 = s.getInterface("b1").?;
    const c0 = s.getInterface("c0").?;

    const app_data = try core.data.makeBytes("here is some app data", ally);
    try a0.api.announce(a.node.mainEndpoint(), app_data);
    try s.stepAfter(1, .seconds, &manual_clock);
    try t.expect(a0.event_buffer.items.len == 0);
    try s.stepAfter(1, .seconds, &manual_clock);
    try t.expect(a0.event_buffer.items.len == 1);

    inline for (&.{ b0, b1, c0 }) |n| {
        try t.expect(n.event_buffer.items.len == 0);
    }

    var announce = a0.event_buffer.items[0];

    try golden.snap(
        @src(),
        \\.packet = .{
        \\  .header = .{.open, .normal, .some, .broadcast, .single, .announce, hops(0)},
        \\  .endpoints = .normal{71cb75e4effb51744aa9877da2b9af56},
        \\  .context = .none,
        \\  .payload = .announce{
        \\    .public.dh = a88fb9b46bb5d1a9edacf671c0b6b0f73ecabdf4a6c86850659ffa907a9ce16f,
        \\    .public.signature = 921dced131de7b57813d215b0785df8375f6d3bd046a872846e695af820222a6,
        \\    .name_hash = ca978112ca1bbdcafac2,
        \\    .noise = 9325ba36e2,
        \\    .timestamp = 000000000a,
        \\    .ratchet = 3cd8d216726b89248c7e1ae8d32e176dbb4c25dfbfa4edf2373f70c6c642ff85,
        \\    .signature = ca87af796f5ab949ea7e44e0e618a973f558fe81a676d536d022c47e300dba8164dae7a4e51d66b2b5d22ad5ef92b77558cc889710758bac97d1846ce34b6c0b,
        \\    .application_data = 6865726520697320736f6d65206170702064617461,
        \\  },
        \\}
        ,
    ).expectEqualFmt(announce);

    try s.stepAfter(10, .microseconds, &manual_clock);
    try t.expect(b1.event_buffer.items.len == 1);

    inline for (&.{ a0, b0, c0 }) |n| {
        try t.expect(n.event_buffer.items.len == 0);
    }

    try t.expect(b.node.routes.has(a.node.mainEndpoint().short().*));

    announce = b1.event_buffer.items[0];

    try golden.snap(
        @src(),
        \\.packet = .{
        \\  .header = .{.open, .transport, .some, .broadcast, .single, .announce, hops(1)},
        \\  .endpoints = .transport{71cb75e4effb51744aa9877da2b9af56, f81ae61e99c1e826604cf1e5880c6847},
        \\  .context = .none,
        \\  .payload = .announce{
        \\    .public.dh = a88fb9b46bb5d1a9edacf671c0b6b0f73ecabdf4a6c86850659ffa907a9ce16f,
        \\    .public.signature = 921dced131de7b57813d215b0785df8375f6d3bd046a872846e695af820222a6,
        \\    .name_hash = ca978112ca1bbdcafac2,
        \\    .noise = 9325ba36e2,
        \\    .timestamp = 000000000a,
        \\    .ratchet = 3cd8d216726b89248c7e1ae8d32e176dbb4c25dfbfa4edf2373f70c6c642ff85,
        \\    .signature = ca87af796f5ab949ea7e44e0e618a973f558fe81a676d536d022c47e300dba8164dae7a4e51d66b2b5d22ad5ef92b77558cc889710758bac97d1846ce34b6c0b,
        \\    .application_data = 6865726520697320736f6d65206170702064617461,
        \\  },
        \\}
        ,
    ).expectEqualFmt(announce);

    try s.stepAfter(10, .microseconds, &manual_clock);

    inline for (&.{ a0, b0, b1, c0 }) |n| {
        try t.expect(n.event_buffer.items.len == 0);
    }
}
