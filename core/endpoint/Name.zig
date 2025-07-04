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
        .app_name = .init(ally),
        .aspects = .init(ally),
        .hash = undefined,
    };

    errdefer {
        self.app_name.deinit();
        self.aspects.deinit();
    }

    for (app_name) |char| {
        if (char == '.') {
            return Error.InvalidName;
        }
    }

    try self.app_name.appendSlice(app_name);

    for (aspects) |aspect| {
        for (aspect) |char| {
            if (char == '.') {
                return Error.InvalidAspect;
            }
        }

        var new_aspect = Aspect.init(self.ally);
        errdefer {
            new_aspect.deinit();
        }

        try new_aspect.appendSlice(aspect);
        try self.aspects.append(new_aspect);
    }

    self.hash = blk: {
        var name = data.Bytes.init(self.ally);
        defer {
            name.deinit();
        }

        try name.appendSlice(app_name);

        for (aspects) |aspect| {
            try name.append('.');
            try name.appendSlice(aspect);
        }

        break :blk Hash.ofData(name.items);
    };

    return self;
}

pub fn clone(self: *Self) !Self {
    var cloned = self.*;
    cloned.app_name = try cloned.app_name.clone();
    cloned.aspects = Aspects.init(self.ally);

    for (self.aspects) |aspect| {
        cloned.aspects.append(try aspect.clone());
    }

    return cloned;
}

pub fn deinit(self: *Self) void {
    self.app_name.deinit();

    for (self.aspects.items) |aspect| {
        aspect.deinit();
    }

    self.aspects.deinit();
    self.* = undefined;
}
