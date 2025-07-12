const builtin = @import("builtin");
const std = @import("std");
const crypto = @import("crypto.zig");

const Allocator = std.mem.Allocator;
const Hash = crypto.Hash;
const Ratchet = [32]u8;
const System = @import("System.zig");

const Self = @This();

const Entry = struct {
    ratchets: std.fifo.LinearFifo(Ratchet, .Dynamic),
    last_rotation_time: u64,
};

const max_ratchets = if (builtin.os.tag == .freestanding) 32 else 256;
const rotation_period = 30 * std.time.us_per_min;

ally: Allocator,
entries: std.StringArrayHashMap(Entry),
rng: *System.Rng,

pub fn init(ally: Allocator, rng: *System.Rng) Self {
    return Self{
        .ally = ally,
        .entries = std.StringArrayHashMap(Entry).init(ally),
        .rng = rng,
    };
}

pub fn add(self: *Self, endpoint: Hash.Short, now: u64) !Ratchet {
    if (self.entries.contains(&endpoint)) {
        return error.EntryAlreadyExists;
    }

    const key = try self.ally.dupe(u8, &endpoint);

    try self.entries.put(key, .{
        .ratchets = self.ally,
        .last_rotation_time = now,
    });

    const ratchet = try self.getRatchet(&endpoint, now) orelse unreachable;
    return ratchet;
}

pub fn getRatchet(self: *Self, endpoint: Hash.Short, now: u64) !?Ratchet {
    if (self.entries.getPtr(&endpoint)) |entry| {
        const needs_rotating = now - entry.last_rotation_time >= rotation_period;

        if (needs_rotating) {
            var seed: [crypto.X25519.seed_length]u8 = undefined;
            self.rng.bytes(&seed);

            const ratchet = try crypto.X25519.KeyPair.generateDeterministic(seed);

            if (entry.ratchets.count >= max_ratchets) {
                entry.ratchets.discard(1);
            }

            entry.ratchets.writeItem(ratchet.public_key);
            entry.last_rotation_time = now;
        }

        return entry.ratchets.peekItem(entry.ratchets.count - 1);
    }

    return null;
}

pub fn deinit(self: *Self) void {
    var entries = self.entries.iterator();

    while (entries.next()) |entry| {
        self.ally.free(entry.key_ptr.*);
        entry.value_ptr.ratchets.deinit();
    }

    self.entries.deinit();
    self.* = undefined;
}
