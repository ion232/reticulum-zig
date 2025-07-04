const std = @import("std");
const crypto = @import("../crypto.zig");
const data = @import("../data.zig");
const endpoint = @import("../endpoint.zig");

const Allocator = std.mem.Allocator;
const Identity = crypto.Identity;
const Direction = endpoint.Direction;
const Method = endpoint.Method;
const Name = endpoint.Name;
const Hash = crypto.Hash;

const Self = @This();

ally: Allocator,
identity: ?Identity,
direction: Direction,
method: Method,
name: Name,
hash: Hash,

pub fn clone(self: *const Self) !Self {
    return Self{
        .ally = self.ally,
        .identity = self.identity,
        .direction = self.direction,
        .method = self.method,
        .name = try self.name.clone(),
        .hash = self.hash,
    };
}

pub fn deinit(self: *Self) void {
    self.name.deinit();
    self.* = undefined;
}
