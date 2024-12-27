const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

const Self = @This();

pub const long_length: usize = Sha256.digest_length;
pub const short_length: usize = long_length / 2;

bytes: [long_length]u8,

pub fn from_items(items: anytype) Self {
    var hash = Self{ .bytes = undefined };
    var hasher = Sha256.init(.{});

    inline for (std.meta.fields(@TypeOf(items))) |field| {
        const value = @field(items, field.name);
        switch (@TypeOf(value)) {
            []const u8, []u8 => hasher.update(value),
            else => switch (@typeInfo(@TypeOf(value))) {
                .Int => hasher.update(std.mem.asBytes(&value)),
                .Array => |_| hasher.update(std.mem.sliceAsBytes(value[0..])),
                else => @compileError("Unsupported type: " + @typeName(@TypeOf(value))),
            },
        }
    }

    hasher.final(hash[0..long_length]);

    return hash;
}

pub fn long(self: *Self) *const [long_length]u8 {
    return self.bytes[long_length];
}

pub fn short(self: *Self) *const [short_length]u8 {
    return self.bytes[short_length];
}
