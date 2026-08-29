const std = @import("std");
const adt = @import("../../adt.zig");
const crypto = @import("../crypto.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @import("Managed.zig");
const Identity = crypto.Identity;
const Interface = @import("../Interface.zig");
const Ratchet = Identity.Ratchet;
const PublicKeys = Identity.PublicKeys;
const StringMap = adt.StringMap;
const Hash = crypto.Hash;
const Rng = @import("../System.zig").Rng;

const Self = @This();

const Entry = struct {
    endpoint: Endpoint,
};

ally: Allocator,
main: Endpoint,
entries: StringMap(Entry),

pub fn init(ally: Allocator, main: *const Endpoint) !Self {
    var self = Self{
        .ally = ally,
        .main = try main.clone(),
        .entries = std.StringArrayHashMap(Entry).init(ally),
    };

    try self.add(main);

    return self;
}

pub fn add(self: *Self, endpoint: *const Endpoint) !void {
    const key = try self.ally.dupe(u8, endpoint.hash.short());
    try self.entries.put(key, Entry{
        .endpoint = try endpoint.clone(),
    });
}

pub fn has(self: *Self, hash: *const Hash.Short) bool {
    return self.get(hash) != null;
}

pub fn getPtr(self: *Self, hash: *const Hash.Short) ?*const Endpoint {
    if (self.entries.getPtr(hash[0..])) |entry| {
        return &entry.endpoint;
    }
    return null;
}

pub fn deinit(self: *Self) void {
    var entries = self.entries.iterator();
    while (entries.next()) |*entry| {
        self.ally.free(entry.key_ptr.*);
        entry.value_ptr.endpoint.deinit();
    }

    self.entries.deinit();
    self.main.deinit();
    self.* = undefined;
}

test "main" {
    const t = std.testing;
    const Builder = @import("Builder.zig");
    const Name = @import("Name.zig");

    const ally = t.allocator;
    var main_endpoint = blk: {
        var builder = Builder.init(ally);
        defer builder.deinit();

        var rng = std.crypto.random;
        const endpoint = try builder
            .setIdentity(try Identity.random(&rng))
            .setName(try Name.init("endpoint", &.{"main"}, ally))
            .setDirection(.in)
            .setVariant(.single)
            .build();

        break :blk endpoint;
    };
    defer main_endpoint.deinit();

    var store = try Self.init(ally, &main_endpoint);
    defer store.deinit();

    const retrieved = store.getPtr(main_endpoint.hash.short()) orelse return error.TestUnexpectedResult;
    try t.expectEqualSlices(u8, &main_endpoint.hash.bytes, &retrieved.hash.bytes);
}
