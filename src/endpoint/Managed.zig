const std = @import("std");
const crypto = @import("../crypto.zig");
const endpoint = @import("../endpoint.zig");

const Allocator = std.mem.Allocator;
const Identity = crypto.Identity;
const Direction = endpoint.Direction;
const Method = endpoint.Method;
const Hash = crypto.Hash;

const Self = @This();

ally: Allocator,
identity: Identity,
direction: Direction,
method: Method,
application_name: *const std.ArrayList(u8),
aspects: *const std.ArrayList(std.ArrayList(u8)),
hash: Hash,
