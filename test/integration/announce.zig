const std = @import("std");
const rt = @import("reticulum");
const t = std.testing;

const Framework = @import("kit/Framework.zig");
const Verifier = @import("ohsnap");
const verifier = Verifier{};

test "announce: a-b-c" {
    const ally = t.allocator;
    var f = try Framework.fromTopology(abc, ally);

    const a = f.getNode("a").?;

    try a.announce(a.node.endpoints.main, "hello world!");
    try f.process("a");

    try verifier.snap(
        @src(),
        \\<!update>
        ,
    ).expectEqualFmt(f.collect("a", "a0"));

    try verifier.snap(
        @src(),
        \\<!update>
        ,
    ).expectEqualFmt(f.collect("a", "a0"));
}

const abc = .{
    .a = .{
        .interfaces = .{
            .a0 = .{
                .to = .{.b0},
            },
        },
    },
    .b = .{
        .options = .{
            .name = "b",
            .transport_enable = true,
            .interface_limit = 256,
            .incoming_packets_limit = 1024,
            .outgoing_packets_limit = 1024,
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
