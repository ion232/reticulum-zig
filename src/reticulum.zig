const std = @import("std");
const crypto = @import("crypto/crypto.zig");
const endpoint = @import("endpoint/endpoint.zig");

const Allocator = std.mem.Allocator;
pub const Sources = @import("sources.zig").Sources;

pub const Reticulum = struct {
    ally: Allocator,
    sources: Sources,

    pub fn init(ally: Allocator, sources: Sources) Reticulum {
        return .{
            .ally = ally,
            .sources = sources,
        };
    }
};
