const std = @import("std");
const crypto = @import("../crypto.zig");
const endpoint = @import("../endpoint.zig");

const Allocator = std.mem.Allocator;
const Bytes = @import("../internal/Bytes.zig");
const Identity = crypto.Identity;
const Direction = endpoint.Direction;
const Method = endpoint.Method;
const Hash = crypto.Hash;
const Managed = @import("Managed.zig");

const Self = @This();
const Fields = std.bit_set.IntegerBitSet(std.meta.fields(Managed).len - 3);

pub const Error = error{Incomplete};

ally: Allocator,
fields: Fields,
identity: Identity = undefined,
direction: Direction = undefined,
method: Method = undefined,
application_name: Bytes,
aspects: std.ArrayList(Bytes),

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .fields = Fields.initEmpty(),
        .application_name = Bytes.init(ally),
        .aspects = Bytes.init(ally),
    };
}

pub fn set_identity(self: *Self, identity: Identity) *Self {
    self.fields.set(0);
    self.identity = identity;
    return self;
}

pub fn set_direction(self: *Self, direction: Direction) *Self {
    self.fields.set(1);
    self.direction = direction;
    return self;
}

pub fn set_method(self: *Self, method: Method) *Self {
    self.fields.set(2);
    self.method = method;
    return self;
}

pub fn set_application_name(self: *Self, application_name: []const u8) *Self {
    self.fields.set(3);
    self.application_name = Bytes.init(self.ally);
    self.application_name.appendSlice(application_name);
    return self;
}

pub fn append_aspect(self: *Self, aspect: []const u8) *Self {
    const managed_aspect = Bytes.init(self.ally);
    managed_aspect.appendSlice(aspect);
    self.aspects.append(managed_aspect);
    return self;
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
            .hash = Hash.from_items(.{}),
        };
    }

    return Error.Incomplete;
}
