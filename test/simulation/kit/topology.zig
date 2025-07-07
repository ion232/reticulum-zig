//!   ┌────────┐    ┌─────────┐    ┌────────┐
//!   │   a0───┼────┼─b0[T]b1─┼────┼───c0   │
//!   └────────┘    └─────────┘    └────────┘
pub const abc = .{
    .a = .{
        .interfaces = .{
            .a0 = .{ .to = .b0 },
        },
    },
    .b = .{
        .options = .{
            .transport_enabled = true,
        },
        .interfaces = .{
            .b0 = .{ .to = .a0 },
            .b1 = .{ .to = .c0 },
        },
    },
    .c = .{
        .interfaces = .{
            .c0 = .{ .to = .b1 },
        },
    },
};
