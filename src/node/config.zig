const Self = @This();

authenticated: bool = false,
max_incoming_packets: usize = 1024,
max_outgoing_packets: usize = 1024,
