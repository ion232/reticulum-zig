const std = @import("std");

// TODO: Add storage interface.
pub const Os = @import("system/Os.zig");
pub const Clock = @import("system/Clock.zig");
pub const Rng = std.Random;

clock: Clock,
rng: Rng,
