const Identity = @import("../crypto/Identity.zig");

const Self = @This();

// TODO: Load the version from build.zig.zon.
name: []const u8 = "reticulum-zig",
transport_enabled: bool = false,
incoming_packets_limit: usize = 1024,
outgoing_packets_limit: usize = 1024,
