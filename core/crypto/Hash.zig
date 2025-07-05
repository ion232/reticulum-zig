const std = @import("std");
const data = @import("../data.zig");

const Sha256 = std.crypto.hash.sha2.Sha256;

const Self = @This();

pub const Incremental = Sha256;

pub const long_length: usize = Sha256.digest_length;
pub const short_length: usize = long_length / 2;
pub const name_length: usize = 10;
// 0.0007% collision chance for 1_000_000 packets.
// Could go down to 6 at 0.0018% chance for 100_000 packets. Needs investigation.
pub const packet_length: usize = 7;

pub const Long = [long_length]u8;
pub const Short = [short_length]u8;
pub const Name = [name_length]u8;
pub const Packet = [packet_length]u8;

bytes: [long_length]u8,

pub fn fromLong(hash: Long) Self {
    return .{
        .bytes = hash,
    };
}

pub fn of(items: anytype) Self {
    var hasher = incremental(items);
    return Self.fromLong(hasher.finalResult());
}

pub fn incremental(items: anytype) Incremental {
    var hasher = Incremental.init(.{});

    inline for (std.meta.fields(@TypeOf(items))) |field| {
        const value = @field(items, field.name);
        switch (@TypeOf(value)) {
            u8 => hasher.update(&.{value}),
            []const u8, []u8 => hasher.update(value),
            []const data.Bytes => |bytes_list| {
                for (bytes_list) |bytes| {
                    hasher.update(bytes.items);
                }
            },
            *const Long => hasher.update(value),
            *const Short => hasher.update(value),
            *const Name => hasher.update(value),
            [long_length]u8 => hasher.update(&value),
            [short_length]u8 => hasher.update(&value),
            [name_length]u8 => hasher.update(&value),
            else => switch (@typeInfo(@TypeOf(value))) {
                else => @compileError("Unsupported type: " ++ @typeName(@TypeOf(value))),
            },
        }
    }

    return hasher;
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

pub fn packet(self: *const Self) *const Packet {
    return self.bytes[0..packet_length];
}
