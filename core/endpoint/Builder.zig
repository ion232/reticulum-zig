const std = @import("std");
const crypto = @import("../crypto.zig");
const endpoint = @import("../endpoint.zig");

const Allocator = std.mem.Allocator;
const Bytes = std.ArrayList(u8);
const Identity = crypto.Identity;
const Direction = endpoint.Direction;
const Method = endpoint.Method;
const Hash = crypto.Hash;
const Managed = @import("Managed.zig");

const Self = @This();
const Fields = std.bit_set.IntegerBitSet(std.meta.fields(Managed).len - 4);

pub const Error = error{
    Incomplete,
    InvalidName,
    InvalidAspect,
} || Allocator.Error;

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
        .aspects = std.ArrayList(Bytes).init(ally),
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

pub fn set_application_name(self: *Self, application_name: []const u8) !*Self {
    self.fields.set(3);
    self.application_name = Bytes.init(self.ally);
    try self.application_name.appendSlice(application_name);
    return self;
}

pub fn append_aspect(self: *Self, aspect: []const u8) !*Self {
    var managed_aspect = Bytes.init(self.ally);
    try managed_aspect.appendSlice(aspect);
    try self.aspects.append(managed_aspect);
    return self;
}

pub fn build(self: *Self) Error!Managed {
    errdefer {
        self.application_name.clearAndFree();

        for (self.aspects.items) |*a| {
            a.clearAndFree();
        }

        self.aspects.clearAndFree();
    }

    if (self.fields.count() == self.fields.capacity()) {
        const name_hash = blk: {
            // TODO: Do this incrementally without copying.
            var name_bytes = Bytes.init(self.ally);
            try name_bytes.appendSlice(self.application_name.items);

            errdefer {
                name_bytes.deinit();
            }

            for (self.application_name.items) |c| {
                if (c == '.') {
                    return Error.InvalidName;
                }
            }

            for (self.aspects.items) |a| {
                for (a.items) |c| {
                    if (c == '.') {
                        return Error.InvalidAspect;
                    }
                }

                try name_bytes.append('.');
                try name_bytes.appendSlice(a.items);
            }

            break :blk Hash.hash_data(name_bytes.items);
        };

        const hash = Hash.hash_items(.{
            .name_hash = name_hash.name(),
            .identity_hash = self.identity.hash.short(),
        });

        return Managed{
            .ally = self.ally,
            .identity = self.identity,
            .direction = self.direction,
            .method = self.method,
            .application_name = self.application_name,
            .aspects = self.aspects,
            .hash = hash,
            .name_hash = name_hash,
        };
    }

    return Error.Incomplete;
}
