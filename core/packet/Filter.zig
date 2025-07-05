const std = @import("std");

const Allocator = std.mem.Allocator;
const Packet = @import("Managed.zig");
const Hash = @import("../crypto.zig").Hash;

const Self = @This();

ally: Allocator,
// TODO: For embedded this should probably be an LRU cache.
hashes: std.StringArrayHashMap(void),

pub fn init(ally: Allocator, capacity: usize) !Self {
    var hashes = std.StringArrayHashMap(void).init(ally);
    try hashes.ensureTotalCapacity(capacity);

    return .{
        .ally = ally,
        .hashes = hashes,
    };
}

pub fn add(self: *Self, packet: *const Packet) void {
    if (self.hashes.count() == self.hashes.capacity()) {
        var hashes = self.hashes.iterator();
        while (hashes.next()) |entry| {
            self.ally.free(entry.key_ptr.*);
        }
        self.hashes.clearRetainingCapacity();
    }

    const key = self.ally.dupe(u8, packet.hash().packet()) catch return;
    self.hashes.putAssumeCapacity(key, {});
}

pub fn has(self: *const Self, packet: *const Packet) bool {
    return self.hashes.contains(packet.hash().packet());
}

pub fn deinit(self: *Self) void {
    var hashes = self.hashes.iterator();
    while (hashes.next()) |entry| {
        self.ally.free(entry.key_ptr.*);
    }
    self.hashes.deinit();
    self.* = undefined;
}
