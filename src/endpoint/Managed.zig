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
