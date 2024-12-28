const std = @import("std");
const crypto = @import("../crypto.zig");
const endpoint = @import("../endpoint.zig");

const Allocator = std.mem.Allocator;
const Identity = crypto.Identity;
const Direction = endpoint.Direction;
const Method = endpoint.Method;
const Managed = @import("Managed.zig");

const Self = @This();
const Fields = std.bit_set.IntegerBitSet(std.meta.fields(Managed).len - 2);

pub const Error = error{
    Incomplete,
};

ally: Allocator,
fields: Fields,
identity: Identity = undefined,
direction: Direction = undefined,
method: Method = undefined,
application_name: *std.ArrayList(u8) = undefined,
aspects: *std.ArrayList(std.ArrayList(u8)) = undefined,

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .fields = Fields.initEmpty(),
    };
}

pub fn identity(self: *Self, new_identity: Identity) *Self {
    self.fields.set(0);
    self.identity = new_identity;
}

pub fn direction(self: *Self, new_direction: Direction) *Self {
    self.fields.set(1);
    self.direction = new_direction;
}

pub fn method(self: *Self, new_method: Method) *Self {
    self.fields.set(2);
    self.method = new_method;
}

pub fn application_name(self: *Self, new_application_name: []const u8) *Self {
    self.fields.set(3);
    self.application_name = new_application_name;
}

pub fn add_aspect(self: *Self, new_aspect: []const u8) *Self {
    const aspect = std.ArrayList(u8).init(self.ally);
    aspect.appendSlice(new_aspect);
    self.aspects.append(aspect);
}

pub fn build(self: *Self) Error!Managed {
    if (self.fields.count() == self.fields.capacity()) {
        return Managed{
            .ally = self.ally,
            .identity = self.identity,
            .direction = self.direction,
            .method = self.method,
            .application_name = self.application_name,
            .aspects = self.aspects,
        };
    }

    return Error.Incomplete;
}
