const std = @import("std");

// Abstract away via some sort of interface.
// TODO: Make this optionally seeded - probably by a comptime param + lazy evaluation.
var prng = std.rand.DefaultPrng.init(123);
pub const rand = prng.random();
