pub const Bandwidth = BitRate;

pub const BitRate = struct {
    bits: Bits,
    rate: Rate,
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
