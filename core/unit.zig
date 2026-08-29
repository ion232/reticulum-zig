pub const Bandwidth = BitRate;

pub const BitRate = struct {
    pub const none: ?BitRate = null;
    pub const default = BitRate{
        .bits = .{ .count = 1, .prefix = .kilo },
        .rate = .per_second,
    };

    bits: Bits,
    rate: Rate,

    pub fn bitsPerSecond(self: @This()) usize {
        const factor: usize = switch (self.bits.prefix) {
            .none => 1,
            .kilo => 1_000,
            .mega => 1_000_000,
        };

        return factor * self.bits.count;
    }
};

pub const Bits = struct {
    count: usize,
    prefix: Prefix,
};

pub const Prefix = enum {
    none,
    kilo,
    mega,
};

pub const Rate = enum {
    per_second,
};
