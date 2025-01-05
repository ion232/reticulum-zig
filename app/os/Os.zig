const std = @import("std");
const Timer = std.time.Timer;
const System = @import("../System.zig");

pub const Clock = @import("os/Clock.zig");
pub const Rng = @import("os/Rng.zig");

const Self = @This();

clock: Clock,
rng: Rng,

pub fn init() Timer.Error!Self {
    return Self{
        .clock = try Clock.init(),
        .rng = Rng.init(),
    };
}

pub fn system(self: *Self) System {
    return System{
        .clock = self.clock.clock(),
        .rng = self.rng.rng(),
    };
}
