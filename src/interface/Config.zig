const BitRate = @import("../units.zig").BitRate;

const Self = @This();

access_code: ?[]const u8 = null,
initial_bit_rate: BitRate = .{
    .bits = 1000,
    .rate = .per_second,
},
max_held_packets: usize = 1000,
