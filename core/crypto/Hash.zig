const std = @import("std");
const Sha256 = std.crypto.hash.sha2.Sha256;

const Self = @This();

pub const long_length: usize = Sha256.digest_length;
pub const short_length: usize = long_length / 2;
pub const name_length: usize = 10;

pub const Long = [long_length]u8;
pub const Short = [short_length]u8;
pub const Name = [name_length]u8;

bytes: [long_length]u8,

pub fn from_long(hash: Long) Self {
    return .{
        .bytes = hash,
    };
}

pub fn hash_data(data: []const u8) Self {
    return hash_items(.{ .data = data });
}

pub fn hash_items(items: anytype) Self {
    var hash = Self{ .bytes = undefined };
    var hasher = Sha256.init(.{});

    inline for (std.meta.fields(@TypeOf(items))) |field| {
        const value = @field(items, field.name);
        switch (@TypeOf(value)) {
            []const u8, []u8 => hasher.update(value),
            []const std.ArrayList(u8) => |lists| {
                for (lists) |l| {
                    hasher.update(l.items);
                }
            },
            *const Long => hasher.update(value),
            *const Short => hasher.update(value),
            *const Name => hasher.update(value),
            else => switch (@typeInfo(@TypeOf(value))) {
                .Int => hasher.update(std.mem.asBytes(&value)),
                .Array => |_| hasher.update(std.mem.sliceAsBytes(value[0..])),
                else => @compileError("Unsupported type: " ++ @typeName(@TypeOf(value))),
            },
        }
    }

    hasher.final(hash.bytes[0..long_length]);

    return hash;
}

pub fn hex(self: *const Self) [2 * long_length]u8 {
    return std.fmt.bytesToHex(self.bytes, .lower);
}

pub fn long(self: *const Self) *const Long {
    return self.bytes[0..long_length];
}

pub fn short(self: *const Self) *const Short {
    return self.bytes[0..short_length];
}

pub fn name(self: *const Self) *const Name {
    return self.bytes[0..name_length];
}
