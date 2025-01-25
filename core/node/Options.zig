const Identity = @import("../crypto/Identity.zig");

const Self = @This();

// TODO: Load the version from build.zig.zon.
name: []const u8 = "reticulum-zig-0.1.0",
transport_enabled: bool = false,
interface_limit: usize = 256,
incoming_packets_limit: usize = 1024,
outgoing_packets_limit: usize = 1024,
