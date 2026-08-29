const Identity = @import("../crypto/Identity.zig");

const Self = @This();

pub const MemoryAllocation = struct {
    endpoints: usize,
    hashes: usize,
    interfaces: usize,
    ratchets: usize,
    routes: usize,

    pub fn default() @This() {
        // Probably <= 1GB for operating systems and WASM.
        // Otherwise, for freestanding, assume 512KB as this is likely the lower limit.
    }
};

pub const Transport = enum {
    enabled,
    disabled,
};

name: []const u8 = "reticulum-zig",
transport: Transport = .enabled,
memory_allocation: MemoryAllocation = .default()
