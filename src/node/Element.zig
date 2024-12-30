const interface = @import("../interface.zig");
const Packet = @import("../packet.zig").Managed;

pub const In = struct {
    packet: Packet,
};

pub const Out = struct {
    packet: Packet,
};
