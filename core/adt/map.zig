/// Modified from std.array_hash_map.ArrayHashMap.
/// TODO: Look into replacing this with a purpose built implementation.
const std = @import("std");
const df = @import("df.zig");
const t = std.testing;

const Allocator = std.mem.Allocator;

pub fn StringMap(comptime V: type, comptime I: type) type {
    return Map([]const u8, V, I, StringOps);
}

pub const StringOps = struct {
    var seed: u64 = 0;

    fn hash(k: []const u8) u32 {
        return @truncate(std.hash.Wyhash.hash(@This().seed, k));
    }

    fn eql(a: []const u8, b: []const u8) bool {
        return std.mem.eql(u8, a, b);
    }
};

pub fn Map(
    comptime K: type,
    comptime V: type,
    comptime I: type,
    comptime Ops: type,
) type {
    comptime {
        if (I != u8 and I != u16 and I != u32) {
            @compileError("Invalid index backing type.");
        }
    }

    return struct {
        pub const KV = struct {
            key: K,
            value: V,
        };

        pub const Entry = struct {
            key_ptr: *K,
            value_ptr: *V,
        };

        pub const Iterator = struct {
            keys: [*]K,
            values: [*]V,
            len: u32,
            index: u32 = 0,

            pub fn next(it: *Iterator) ?Entry {
                if (it.index >= it.len) return null;
                const result = Entry{
                    .key_ptr = &it.keys[it.index],
                    .value_ptr = if (@sizeOf(*V) == 0) undefined else &it.values[it.index],
                };
                it.index += 1;
                return result;
            }
        };

        const IndexHeader = struct {
            const max_representable_index_len = @bitSizeOf(usize) - 4;
            const max_bit_index = @min(32, max_representable_index_len);
            const min_bit_index = 5;
            const max_capacity = (1 << max_bit_index) - 1;
            const index_capacities = blk: {
                var caps: [max_bit_index + 1]u32 = undefined;
                for (caps[0..max_bit_index], 0..) |*item, i| {
                    item.* = (1 << i) * 3 / 5;
                }
                caps[max_bit_index] = max_capacity;
                break :blk caps;
            };

            bit_index: u8 align(@alignOf(u32)),

            fn init(allocator: Allocator, capacity: usize) Allocator.Error!*IndexHeader {
                if (capacity >= std.math.maxInt(I) or capacity > max_capacity) return error.OutOfMemory;

                var bit_index = @as(u8, @intCast(std.math.log2_int_ceil(usize, capacity)));
                if (capacity > index_capacities[bit_index]) bit_index += 1;
                if (bit_index < min_bit_index) bit_index = min_bit_index;
                std.debug.assert(capacity <= index_capacities[bit_index]);

                const len = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(bit_index));
                const bytes = try allocator.alignedAlloc(u8, @alignOf(IndexHeader), @sizeOf(IndexHeader) + @sizeOf(Index) * len);
                @memset(bytes[@sizeOf(IndexHeader)..], 0xff);

                const result: *IndexHeader = @alignCast(@ptrCast(bytes.ptr));
                result.* = .{ .bit_index = bit_index };

                return result;
            }

            fn deinit(self: *@This(), allocator: Allocator) void {
                const ptr: [*]align(@alignOf(IndexHeader)) u8 = @ptrCast(self);
                const slice = ptr[0 .. @sizeOf(IndexHeader) + self.length() * @sizeOf(Index)];
                allocator.free(slice);
            }

            fn constrainIndex(self: @This(), i: usize) usize {
                const mask: u32 = @intCast(self.length() - 1);
                return @intCast(i & mask);
            }

            fn indexes(self: *@This()) []Index {
                const start_ptr: [*]Index = @alignCast(@ptrCast(@as([*]u8, @ptrCast(self)) + @sizeOf(IndexHeader)));
                return start_ptr[0..self.length()];
            }

            fn length(self: @This()) usize {
                return @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(self.bit_index));
            }

            comptime {
                if (@alignOf(u32) > @alignOf(IndexHeader)) @compileError("IndexHeader must have a larger alignment than its indexes!");
            }
        };

        const Index = extern struct {
            const Self = @This();

            entry_index: I,
            distance_from_start_index: I,

            const empty_sentinel = ~@as(I, 0);

            const empty = @This(){
                .entry_index = empty_sentinel,
                .distance_from_start_index = undefined,
            };

            fn isEmpty(index: @This()) bool {
                return index.entry_index == empty_sentinel;
            }

            fn setEmpty(index: *@This()) void {
                index.entry_index = empty_sentinel;
                index.distance_from_start_index = undefined;
            }
        };

        const Self = @This();

        data_frame: df.DataFrame(KV),
        index_header: *IndexHeader,

        pub fn init(allocator: Allocator, capacity: usize) Allocator.Error!Self {
            var data_frame = try df.DataFrame(KV).init(allocator, capacity);
            errdefer data_frame.deinit(allocator);
            const index_header = try IndexHeader.init(allocator, capacity);

            return .{
                .data_frame = data_frame,
                .index_header = index_header,
            };
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.data_frame.deinit(allocator);
            self.index_header.deinit(allocator);
            self.* = undefined;
        }

        pub fn get(self: Self, key: K) ?*V {
            const slot = self.getSlotByKey(key) orelse return null;
            const indexes = self.index_header.indexes();
            const index = indexes[slot].entry_index;

            return if (@sizeOf(*V) == 0) @as(*V, undefined) else &self.values()[index];
        }

        pub fn put(self: *Self, key: K, value: V) error{OutOfMemory}!void {
            if (self.data_frame.len >= self.data_frame.capacity) return error.OutOfMemory;

            const slice = self.data_frame.slice();
            const keys_array = slice.items(.key);
            const values_array = slice.items(.value);
            const indexes = self.index_header.indexes();

            const h = Ops.hash(key);
            const start_index = safeTruncate(usize, h);
            const end_index = start_index +% indexes.len;

            var index = start_index;
            var distance_from_start_index: I = 0;

            while (index != end_index) : ({
                index +%= 1;
                distance_from_start_index += 1;
            }) {
                var slot = self.index_header.constrainIndex(index);
                var slot_data = indexes[slot];

                if (slot_data.isEmpty()) {
                    const new_index = self.data_frame.addRow();
                    indexes[slot] = .{
                        .distance_from_start_index = distance_from_start_index,
                        .entry_index = @as(I, @intCast(new_index)),
                    };

                    const key_ptr = &keys_array.ptr[new_index];
                    const value_ptr = if (@sizeOf(*V) == 0) undefined else &values_array.ptr[new_index];
                    key_ptr.* = key;
                    value_ptr.* = value;
                    return;
                }

                const i = slot_data.entry_index;

                if (Ops.eql(key, keys_array[i])) {
                    const value_ptr = if (@sizeOf(*V) == 0) undefined else &values_array[slot_data.entry_index];
                    value_ptr.* = value;
                    return;
                }

                if (slot_data.distance_from_start_index >= distance_from_start_index) continue;

                const new_index = self.data_frame.addRow();
                indexes[slot] = .{
                    .entry_index = @as(I, @intCast(new_index)),
                    .distance_from_start_index = distance_from_start_index,
                };
                distance_from_start_index = slot_data.distance_from_start_index;
                var displaced_index = slot_data.entry_index;

                index +%= 1;
                distance_from_start_index += 1;

                while (index != end_index) : ({
                    index +%= 1;
                    distance_from_start_index += 1;
                }) {
                    slot = self.index_header.constrainIndex(index);
                    slot_data = indexes[slot];

                    if (slot_data.isEmpty()) {
                        indexes[slot] = .{
                            .entry_index = displaced_index,
                            .distance_from_start_index = distance_from_start_index,
                        };

                        const key_ptr = &keys_array.ptr[new_index];
                        const value_ptr = if (@sizeOf(*V) == 0) undefined else &values_array.ptr[new_index];
                        key_ptr.* = key;
                        value_ptr.* = value;
                        return;
                    }

                    if (slot_data.distance_from_start_index < distance_from_start_index) {
                        indexes[slot] = .{
                            .entry_index = displaced_index,
                            .distance_from_start_index = distance_from_start_index,
                        };

                        displaced_index = slot_data.entry_index;
                        distance_from_start_index = slot_data.distance_from_start_index;
                    }
                }
            }

            unreachable;
        }

        pub fn remove(self: *Self, key: K) void {
            const indexes = self.index_header.indexes();
            var slot = self.getSlotByKey(key) orelse return;
            const entry_index = indexes[slot].entry_index;
            self.removeSlot(slot);
            const last_index = self.data_frame.len - 1;

            if (last_index != entry_index) {
                slot = self.getSlotByIndex(last_index);
                indexes[slot].entry_index = @as(I, @intCast(entry_index));
            }

            self.data_frame.remove(entry_index);
        }

        pub fn contains(self: *Self, key: *K) ?*V {
            return self.get(key) != null;
        }

        pub fn count(self: Self) usize {
            return self.data_frame.len;
        }

        pub fn keys(self: Self) []K {
            return self.data_frame.items(.key);
        }

        pub fn values(self: Self) []V {
            return self.data_frame.items(.value);
        }

        pub fn iterator(self: Self) Iterator {
            const slice = self.data_frame.slice();
            return .{
                .keys = slice.items(.key).ptr,
                .values = slice.items(.value).ptr,
                .len = @as(u32, @intCast(slice.len)),
            };
        }

        fn removeSlot(self: *Self, removed_slot: usize) void {
            const indexes = self.index_header.indexes();
            const start_index = removed_slot +% 1;
            const end_index = start_index +% indexes.len;

            var last_slot = removed_slot;
            var index: usize = start_index;

            while (index != end_index) : (index +%= 1) {
                const slot = self.index_header.constrainIndex(index);
                const slot_data = indexes[slot];

                if (slot_data.isEmpty() or slot_data.distance_from_start_index == 0) {
                    indexes[last_slot].setEmpty();
                    return;
                }

                indexes[last_slot] = .{
                    .entry_index = slot_data.entry_index,
                    .distance_from_start_index = slot_data.distance_from_start_index - 1,
                };

                last_slot = slot;
            }

            unreachable;
        }

        fn getSlotByKey(self: Self, key: K) ?usize {
            const slice = self.data_frame.slice();
            const keys_array = slice.items(.key);
            const h = Ops.hash(key);

            const indexes = self.index_header.indexes();
            const start_index = safeTruncate(usize, h);
            const end_index = start_index +% indexes.len;

            var index = start_index;
            var distance_from_start_index: I = 0;

            while (index != end_index) : ({
                index +%= 1;
                distance_from_start_index += 1;
            }) {
                const slot = self.index_header.constrainIndex(index);
                const slot_data = indexes[slot];

                if (slot_data.isEmpty() or slot_data.distance_from_start_index < distance_from_start_index) return null;

                const i = slot_data.entry_index;

                if (Ops.eql(key, keys_array[i])) return slot;
            }

            unreachable;
        }

        fn getSlotByIndex(self: *Self, entry_index: usize) usize {
            const indexes = self.index_header.indexes();
            const slice = self.data_frame.slice();
            const h = Ops.hash(slice.items(.key)[entry_index]);
            const start_index = safeTruncate(usize, h);
            const end_index = start_index +% indexes.len;

            var index = start_index;
            var distance_from_start_index: I = 0;

            while (index != end_index) : ({
                index +%= 1;
                distance_from_start_index += 1;
            }) {
                const slot = self.index_header.constrainIndex(index);
                const slot_data = indexes[slot];

                std.debug.assert(!slot_data.isEmpty());
                std.debug.assert(slot_data.distance_from_start_index >= distance_from_start_index);

                if (slot_data.entry_index == entry_index) return slot;
            }

            unreachable;
        }
    };
}

fn safeTruncate(comptime T: type, val: anytype) T {
    if (@bitSizeOf(T) >= @bitSizeOf(@TypeOf(val))) {
        return val;
    } else {
        return @as(T, @truncate(val));
    }
}

test "basic" {
    var map = try StringMap(i32, u8).init(t.allocator, 7);
    defer map.deinit(t.allocator);

    try t.expectEqual(null, map.get("x"));
    try map.put("x", 123);
    try t.expectEqual(123, map.get("x").?.*);

    try map.put("y", 456);
    try t.expectEqual(456, map.get("y").?.*);

    try map.put("x", -321);
    try t.expectEqual(-321, map.get("x").?.*);

    try map.put("y", 654);
    try t.expectEqual(654, map.get("y").?.*);

    map.remove("x");
    try t.expectEqual(null, map.get("x"));
    try t.expectEqual(654, map.get("y").?.*);

    map.remove("y");
    try t.expectEqual(null, map.get("y"));
    try map.put("y", 321);
    try t.expectEqual(321, map.get("y").?.*);

    try map.put("x", 7);
    try t.expectEqual(7, map.get("x").?.*);
    try map.put("x", 7);
    try t.expectEqual(7, map.get("x").?.*);

    try map.put("z", 1);
    try t.expectEqual(1, map.get("z").?.*);
    try map.put("a", 2);
    try t.expectEqual(2, map.get("a").?.*);
    try map.put("b", 3);
    try t.expectEqual(3, map.get("b").?.*);
    try map.put("c", 4);
    try t.expectEqual(4, map.get("c").?.*);
    try map.put("d", 5);
    try t.expectEqual(5, map.get("d").?.*);

    try t.expectError(error.OutOfMemory, map.put("e", 6));
}

test "iterator" {
    var map = try StringMap(usize, u8).init(t.allocator, 10);
    defer map.deinit(t.allocator);

    const keys = [10][]const u8{ "a", "b", "c", "d", "e", "f", "g", "h", "i", "j" };

    for (keys, 0..) |k, v| {
        try map.put(k, v);
    }

    var i: usize = 0;
    var entries = map.iterator();

    while (entries.next()) |entry| : (i += 1) {
        try t.expectEqualSlices(u8, keys[i], entry.key_ptr.*);
        try t.expectEqual(i, entry.value_ptr.*);
    }
}

test "capacity-exceeds-index-size" {
    var map_u8 = try StringMap(usize, u8).init(t.allocator, std.math.maxInt(u8) - 1);
    defer map_u8.deinit(t.allocator);
    var map_u16 = try StringMap(usize, u16).init(t.allocator, std.math.maxInt(u16) - 1);
    defer map_u16.deinit(t.allocator);

    try t.expectError(error.OutOfMemory, StringMap(usize, u8).init(t.allocator, std.math.maxInt(u8)));
    try t.expectError(error.OutOfMemory, StringMap(usize, u16).init(t.allocator, std.math.maxInt(u16)));
}

test "large-map" {
    const IntOps = struct {
        fn hash(k: usize) u32 {
            return @truncate(std.hash.Wyhash.hash(0, &std.mem.toBytes(k)));
        }

        fn eql(a: usize, b: usize) bool {
            return a == b;
        }
    };

    const capacity = 1_000_000;
    var map = try Map(usize, usize, u32, IntOps).init(t.allocator, capacity);
    defer map.deinit(t.allocator);

    for (0..capacity) |i| {
        try t.expectEqual(null, map.get(i));
    }

    for (0..capacity) |i| {
        try map.put(i, i + 7);
    }

    for (0..capacity) |i| {
        try t.expectEqual(i + 7, map.get(i).?.*);
    }

    for (0..capacity) |i| {
        map.remove(i);
    }

    for (0..capacity) |i| {
        try t.expectEqual(null, map.get(i));
    }
}

test "void-value" {
    var map = try StringMap(void, u8).init(t.allocator, 8);
    defer map.deinit(t.allocator);

    try map.put("x", {});
    try t.expectEqual({}, map.get("x").?.*);
    map.remove("x");
    try t.expectEqual(null, map.get("x"));
    try map.put("x", {});
    try t.expectEqual({}, map.get("x").?.*);

    try t.expectEqual(null, map.get("y"));
    try map.put("y", {});
    try t.expectEqual({}, map.get("y").?.*);
}
