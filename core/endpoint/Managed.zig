const std = @import("std");
const crypto = @import("../crypto.zig");
const data = @import("../data.zig");
const endpoint = @import("../endpoint.zig");

const Allocator = std.mem.Allocator;
const Identity = crypto.Identity;
const Direction = endpoint.Direction;
const Variant = endpoint.Variant;
const Name = endpoint.Name;
const Hash = crypto.Hash;

const Self = @This();

ally: Allocator,
identity: ?Identity,
direction: Direction,
variant: Variant,
name: Name,
hash: Hash,

pub fn clone(self: *const Self) !Self {
    return Self{
        .ally = self.ally,
        .identity = self.identity,
        .direction = self.direction,
        .variant = self.variant,
        .name = try self.name.clone(),
        .hash = self.hash,
    };
}

pub fn deinit(self: *Self) void {
    self.name.deinit();
    self.* = undefined;
}
