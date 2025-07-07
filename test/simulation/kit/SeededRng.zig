const std = @import("std");

const Self = @This();

const Prng = std.Random.DefaultPrng;

prng: Prng,

pub fn init(seed: u64) Self {
    return .{
        .prng = Prng.init(seed),
    };
}

pub fn rng(self: *Self) std.Random {
    return self.prng.random();
}
