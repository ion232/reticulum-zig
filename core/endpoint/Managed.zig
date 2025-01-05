const std = @import("std");
const crypto = @import("../crypto.zig");
const endpoint = @import("../endpoint.zig");

const Allocator = std.mem.Allocator;
const Bytes = std.ArrayList(u8);
const Identity = crypto.Identity;
const Direction = endpoint.Direction;
const Method = endpoint.Method;
const Hash = crypto.Hash;

const Self = @This();

ally: Allocator,
identity: Identity,
direction: Direction,
method: Method,
application_name: Bytes,
aspects: std.ArrayList(Bytes),
hash: Hash,
name_hash: Hash,

pub fn copy(self: *Self) !Self {
    var new = Self{
        .ally = self.ally,
        .identity = self.identity,
        .direction = self.direction,
        .method = self.method,
        .application_name = Bytes.init(self.ally),
        .aspects = std.ArrayList(Bytes).init(self.ally),
        .hash = self.hash,
        .name_hash = self.name_hash,
    };

    try new.application_name.appendSlice(self.application_name.items);

    for (self.aspects.items) |aspect| {
        var new_aspect = Bytes.init(self.ally);
        try new_aspect.appendSlice(aspect.items);
        try new.aspects.append(new_aspect);
    }

    return new;
}
