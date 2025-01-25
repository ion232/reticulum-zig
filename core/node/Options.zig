const Identity = @import("../crypto/Identity.zig");

const Self = @This();

transport_enabled: bool = false,
transport_identity: ?Identity = null,
max_interfaces: usize = 256,
max_incoming_packets: usize = 1024,
max_outgoing_packets: usize = 1024,
