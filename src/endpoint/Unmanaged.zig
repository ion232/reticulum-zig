const std = @import("std");
const crypto = @import("../crypto.zig");
const endpoint = @import("../endpoint.zig");

const Identity = crypto.Identity;
const Direction = endpoint.Direction;
const Method = endpoint.Method;

const Self = @This();

identity: Identity,
direction: Direction,
method: Method,
application_name: []const u8,
aspects: []const []const u8,
