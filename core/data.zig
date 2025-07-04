const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Bytes = std.ArrayList(u8);

pub fn makeBytes(slice: []const u8, ally: Allocator) !Bytes {
    var bytes = Bytes.init(ally);
    try bytes.appendSlice(slice);
    return bytes;
}
