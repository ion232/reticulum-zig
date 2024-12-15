const Interface = @import("interface/interface.zig").Interface;

pub const Node = struct {
    interface: Interface,

    pub fn init(interface: Interface) Node {
        return .{
            .interface = interface,
        };
    }

    pub fn run() !void {
        //
    }
};
