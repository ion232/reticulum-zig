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
const Managed = @import("Managed.zig");

const Self = @This();

pub const Error = error{
    HasIdentity,
    MissingIdentity,
    MissingDirection,
    MissingMethod,
    MissingName,
} || Allocator.Error;

ally: Allocator,
identity: ?Identity,
direction: ?Direction,
method: ?Method,
name: ?Name,

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .identity = null,
        .direction = null,
        .method = null,
        .name = null,
    };
}

pub fn setIdentity(self: *Self, identity: Identity) *Self {
    self.identity = identity;
    return self;
}

pub fn setDirection(self: *Self, direction: Direction) *Self {
    self.direction = direction;
    return self;
}

pub fn setMethod(self: *Self, method: Method) *Self {
    self.method = method;
    return self;
}

pub fn setName(self: *Self, name: Name) *Self {
    self.name = name;
    return self;
}

pub fn build(self: *Self) Error!Managed {
    const direction = self.direction orelse return Error.MissingDirection;
    const method = self.method orelse return Error.MissingMethod;
    const name = self.name orelse return Error.MissingName;

    if (method == .plain and self.identity != null) {
        return Error.HasIdentity;
    } else if (method != .plain and self.identity == null) {
        return Error.MissingIdentity;
    }

    const hash = blk: {
        const name_hash = name.hash.name();

        if (self.identity) |identity| {
            break :blk Hash.ofItems(.{
                .name_hash = name_hash,
                .identity_hash = identity.hash.short(),
            });
        } else {
            break :blk Hash.ofItems(.{
                .name_hash = name_hash,
            });
        }
    };

    return Managed{
        .ally = self.ally,
        .identity = self.identity,
        .direction = direction,
        .method = method,
        .name = name,
        .hash = hash,
    };
}

pub fn deinit(self: *Self) void {
    if (self.name) |name| {
        name.deinit();
    }

    self.* = undefined;
}
