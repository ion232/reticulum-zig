pub const Simulator = @import("simulator.zig").Simulator;

pub const Interface = struct {
    ptr: *anyopaque,
    sendFn: *const fn (ptr: *anyopaque) u64,

    fn send(self: *Interface) u64 {
        return self.sendFn(self.ptr);
    }
};
