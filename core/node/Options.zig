const Self = @This();

transport_enabled: bool = false,
max_interfaces: usize = 256,
max_incoming_packets: usize = 1024,
max_outgoing_packets: usize = 1024,
