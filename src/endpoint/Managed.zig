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

pub fn reversed(self: *Self) Self {
    const new = Self{
        .ally = self.ally,
        .identity = self.identity,
        .direction = switch (self.direction) {
            .in => .out,
            .out => .in,
        },
        .method = self.method,
        .application_name = Bytes.init(self.ally),
        .aspects = std.ArrayList(u8).init(self.ally),
        .hash = self.hash,
        .name_hash = self.name_hash,
    };

    new.application_name.appendSlice(self.application_name);

    for (self.aspects.items) |aspect| {
        const new_aspect = Bytes.init(self.ally);
        new.appendSlice(aspect.items);
        new.aspects.append(new_aspect);
    }

    return new;
}
