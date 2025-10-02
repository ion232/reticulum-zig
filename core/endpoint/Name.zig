const std = @import("std");
const crypto = @import("../crypto.zig");
const data = @import("../data.zig");

const Allocator = std.mem.Allocator;
const Identity = crypto.Identity;
const Hash = crypto.Hash;

const Self = @This();

pub const Error = error{
    InvalidName,
    InvalidAspect,
};

pub const AppName = data.Bytes;
pub const Aspect = data.Bytes;
pub const Aspects = std.ArrayList(Aspect);

ally: Allocator,
app_name: AppName,
aspects: Aspects,
hash: Hash,

pub fn init(app_name: []const u8, aspects: []const []const u8, ally: Allocator) !Self {
    var self = Self{
        .ally = ally,
        .app_name = AppName.empty,
        .aspects = Aspects.empty,
        .hash = undefined,
    };

    errdefer {
        self.app_name.deinit(self.ally);
        self.aspects.deinit(self.ally);
    }

    for (app_name) |char| {
        if (char == '.') {
            return Error.InvalidName;
        }
    }

    try self.app_name.appendSlice(self.ally, app_name);

    for (aspects) |aspect| {
        for (aspect) |char| {
            if (char == '.') {
                return Error.InvalidAspect;
            }
        }

        var new_aspect = Aspect.empty;
        errdefer new_aspect.deinit(self.ally);

        try new_aspect.appendSlice(self.ally, aspect);
        try self.aspects.append(self.ally, new_aspect);
    }

    self.hash = blk: {
        var name = data.Bytes.empty;
        defer name.deinit(self.ally);

        try name.appendSlice(self.ally, app_name);

        for (aspects) |aspect| {
            try name.append(self.ally, '.');
            try name.appendSlice(self.ally, aspect);
        }

        break :blk Hash.of(.{
            .name = name.items,
        });
    };

    return self;
}

pub fn clone(self: *const Self) !Self {
    var cloned = self.*;
    cloned.app_name = try cloned.app_name.clone(self.ally);
    cloned.aspects = Aspects.empty;

    for (self.aspects.items) |aspect| {
        try cloned.aspects.append(self.ally, try aspect.clone(self.ally));
    }

    return cloned;
}

pub fn deinit(self: *Self) void {
    self.app_name.deinit(self.ally);

    for (self.aspects.items) |*aspect| {
        aspect.deinit(self.ally);
    }

    self.aspects.deinit(self.ally);
    self.* = undefined;
}
