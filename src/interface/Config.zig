const BitRate = @import("../units.zig").BitRate;

const Self = @This();

access_code: ?[]const u8 = null,
initial_bit_rate: BitRate = .{
    .bits = .{
        .count = 1,
        .prefix = .kilo,
    },
    .rate = .per_second,
},
max_held_packets: usize = 1000,
