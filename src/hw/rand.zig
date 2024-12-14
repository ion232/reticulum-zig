const std = @import("std");

var prng = std.rand.DefaultPrng.init(1337);
pub const rand = prng.random();
