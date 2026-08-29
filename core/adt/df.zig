/// Modified from std.multi_array_df.MultiArrayList.
const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn DataFrame(comptime T: type) type {
    return struct {
        const Elem = switch (@typeInfo(T)) {
            .@"struct" => T,
            .@"union" => |u| struct {
                pub const Bare = @Type(.{
                    .@"union" = .{
                        .layout = u.layout,
                        .tag_type = null,
                        .fields = u.fields,
                        .decls = &.{},
                    },
                });

                pub const Tag = u.tag_type orelse @compileError("DataFrame does not support untagged unions");

                tags: Tag,
                data: Bare,

                pub fn from(outer: T) @This() {
                    const tag = std.meta.activeTag(outer);
                    return .{
                        .tags = tag,
                        .data = switch (tag) {
                            inline else => |t| @unionInit(Bare, @tagName(t), @field(outer, @tagName(t))),
                        },
                    };
                }
                pub fn to(tag: Tag, bare: Bare) T {
                    return switch (tag) {
                        inline else => |t| @unionInit(T, @tagName(t), @field(bare, @tagName(t))),
                    };
                }
            },
            else => @compileError("DataFrame only supports structs and tagged unions"),
        };

        pub const Field = std.meta.FieldEnum(Elem);

        fn FieldType(comptime field: Field) type {
            return @FieldType(Elem, @tagName(field));
        }

        pub const Slice = struct {
            ptrs: [fields.len][*]u8,
            len: usize,
            capacity: usize,

            pub const empty: Slice = .{
                .ptrs = undefined,
                .len = 0,
                .capacity = 0,
            };

            pub fn deinit(self: *Slice, allocator: Allocator) void {
                var other = self.toDataFrame();
                other.deinit(allocator);
                self.* = undefined;
            }

            pub fn items(self: Slice, comptime field: Field) []FieldType(field) {
                const F = FieldType(field);
                if (self.capacity == 0) {
                    return &[_]F{};
                }
                const byte_ptr = self.ptrs[@intFromEnum(field)];
                const casted_ptr: [*]F = if (@sizeOf(F) == 0) undefined else @ptrCast(@alignCast(byte_ptr));
                return casted_ptr[0..self.len];
            }

            pub fn set(self: *Slice, index: usize, elem: T) void {
                const e = switch (@typeInfo(T)) {
                    .@"struct" => elem,
                    .@"union" => Elem.from(elem),
                    else => unreachable,
                };
                inline for (fields, 0..) |field_info, i| {
                    self.items(@as(Field, @enumFromInt(i)))[index] = @field(e, field_info.name);
                }
            }

            pub fn get(self: Slice, index: usize) T {
                var result: Elem = undefined;
                inline for (fields, 0..) |field_info, i| {
                    @field(result, field_info.name) = self.items(@as(Field, @enumFromInt(i)))[index];
                }
                return switch (@typeInfo(T)) {
                    .@"struct" => result,
                    .@"union" => Elem.to(result.tags, result.data),
                    else => unreachable,
                };
            }

            pub fn toDataFrame(self: Slice) Self {
                if (self.ptrs.len == 0 or self.capacity == 0) {
                    return .{};
                }
                const unaligned_ptr = self.ptrs[sizes.fields[0]];
                const aligned_ptr: [*]align(@alignOf(Elem)) u8 = @alignCast(unaligned_ptr);
                return .{
                    .bytes = aligned_ptr,
                    .len = self.len,
                    .capacity = self.capacity,
                };
            }
        };

        const Self = @This();

        const fields = std.meta.fields(Elem);

        /// `sizes.bytes` is an array of @sizeOf each T field. Sorted by alignment, descending.
        /// `sizes.fields` is an array mapping from `sizes.bytes` array index to field index.
        const sizes = blk: {
            const Data = struct {
                size: usize,
                size_index: usize,
                alignment: usize,
            };
            var data: [fields.len]Data = undefined;
            for (fields, 0..) |field_info, i| {
                data[i] = .{
                    .size = @sizeOf(field_info.type),
                    .size_index = i,
                    .alignment = if (@sizeOf(field_info.type) == 0) 1 else field_info.alignment,
                };
            }
            const Sort = struct {
                fn lessThan(context: void, lhs: Data, rhs: Data) bool {
                    _ = context;
                    return lhs.alignment > rhs.alignment;
                }
            };
            @setEvalBranchQuota(3 * fields.len * std.math.log2(fields.len));
            std.mem.sort(Data, &data, {}, Sort.lessThan);
            var sizes_bytes: [fields.len]usize = undefined;
            var field_indexes: [fields.len]usize = undefined;
            for (data, 0..) |elem, i| {
                sizes_bytes[i] = elem.size;
                field_indexes[i] = elem.size_index;
            }
            break :blk .{
                .bytes = sizes_bytes,
                .fields = field_indexes,
            };
        };

        const Entry = entry: {
            var entry_fields: [fields.len]std.builtin.Type.StructField = undefined;
            for (&entry_fields, sizes.fields) |*entry_field, i| entry_field.* = .{
                .name = fields[i].name ++ "_ptr",
                .type = *fields[i].type,
                .default_value_ptr = null,
                .is_comptime = fields[i].is_comptime,
                .alignment = fields[i].alignment,
            };
            break :entry @Type(.{
                .@"struct" = .{
                    .layout = .@"extern",
                    .fields = &entry_fields,
                    .decls = &.{},
                    .is_tuple = false,
                },
            });
        };

        pub const empty: Self = .{
            .bytes = undefined,
            .len = 0,
            .capacity = 0,
        };

        bytes: [*]align(@alignOf(T)) u8 = undefined,
        len: usize = 0,
        capacity: usize = 0,

        pub fn init(allocator: Allocator, capacity: usize) Allocator.Error!Self {
            var data_frame = Self.empty;

            const bytes = try allocator.alignedAlloc(
                u8,
                @alignOf(Elem),
                capacityInBytes(capacity),
            );

            allocator.free(data_frame.allocatedBytes());
            data_frame.bytes = bytes.ptr;
            data_frame.capacity = capacity;

            return data_frame;
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.allocatedBytes());
            self.* = undefined;
        }

        pub fn slice(self: Self) Slice {
            var result: Slice = .{
                .ptrs = undefined,
                .len = self.len,
                .capacity = self.capacity,
            };
            var ptr: [*]u8 = self.bytes;
            for (sizes.bytes, sizes.fields) |field_size, i| {
                result.ptrs[i] = ptr;
                ptr += field_size * self.capacity;
            }
            return result;
        }

        pub fn items(self: Self, comptime field: Field) []FieldType(field) {
            return self.slice().items(field);
        }

        pub fn set(self: *Self, index: usize, elem: T) void {
            var slices = self.slice();
            slices.set(index, elem);
        }

        pub fn get(self: Self, index: usize) T {
            return self.slice().get(index);
        }

        pub fn push(self: *Self, elem: T) void {
            self.set(self.addRow(), elem);
        }

        pub fn addRow(self: *Self) usize {
            std.debug.assert(self.len < self.capacity);
            const len = self.len;
            self.len += 1;
            return len;
        }

        pub fn pop(self: *Self) ?T {
            if (self.len == 0) return null;
            const val = self.get(self.len - 1);
            self.len -= 1;
            return val;
        }

        pub fn remove(self: *Self, index: usize) void {
            const slices = self.slice();
            inline for (fields, 0..) |_, i| {
                const field_slice = slices.items(@as(Field, @enumFromInt(i)));
                field_slice[index] = field_slice[self.len - 1];
                field_slice[self.len - 1] = undefined;
            }
            self.len -= 1;
        }

        pub fn clone(self: Self, allocator: Allocator) !Self {
            var result = try Self.init(allocator, self.capacity);
            result.len = self.len;

            const self_slice = self.slice();
            const result_slice = result.slice();
            inline for (fields, 0..) |field_info, i| {
                if (@sizeOf(field_info.type) != 0) {
                    const field = @as(Field, @enumFromInt(i));
                    @memcpy(result_slice.items(field), self_slice.items(field));
                }
            }

            return result;
        }

        pub fn capacityInBytes(capacity: usize) usize {
            comptime var elem_bytes: usize = 0;
            inline for (sizes.bytes) |size| elem_bytes += size;
            return elem_bytes * capacity;
        }

        fn allocatedBytes(self: Self) []align(@alignOf(Elem)) u8 {
            return self.bytes[0..capacityInBytes(self.capacity)];
        }
    };
}

test "basic" {
    const t = std.testing;
    const X = struct {
        a: u3,
        b: []const u8,
        c: u8,
    };

    var df = try DataFrame(X).init(t.allocator, 3);
    defer df.deinit(t.allocator);

    try t.expectEqual(@as(usize, 0), df.items(.a).len);

    df.push(.{
        .a = 1,
        .b = "123456",
        .c = 'a',
    });

    df.push(.{
        .a = 2,
        .b = "zigzag",
        .c = 'b',
    });

    try t.expectEqualSlices(u3, df.items(.a), &[_]u3{ 1, 2 });
    try t.expectEqual(@as(usize, 2), df.items(.b).len);
    try t.expectEqualStrings("123456", df.items(.b)[0]);
    try t.expectEqualStrings("zigzag", df.items(.b)[1]);
    try t.expectEqualSlices(u8, df.items(.c), &[_]u8{ 'a', 'b' });

    df.push(.{
        .a = 3,
        .b = "fizzbuzz",
        .c = 'c',
    });

    try t.expectEqualSlices(u3, df.items(.a), &[_]u3{ 1, 2, 3 });
    try t.expectEqualSlices(u8, df.items(.c), &[_]u8{ 'a', 'b', 'c' });

    try t.expectEqual(@as(usize, 3), df.items(.b).len);
    try t.expectEqualStrings("123456", df.items(.b)[0]);
    try t.expectEqualStrings("zigzag", df.items(.b)[1]);
    try t.expectEqualStrings("fizzbuzz", df.items(.b)[2]);

    try t.expectEqualStrings("fizzbuzz", df.pop().?.b);
    try t.expectEqual(@as(u3, 2), df.pop().?.a);
    try t.expectEqual(@as(u8, 'a'), df.pop().?.c);
    try t.expectEqual(@as(?X, null), df.pop());
}

test "clone" {
    const t = std.testing;
    const X = struct {
        a: u3,
        b: []const u8,
        c: u8,
    };

    var df = try DataFrame(X).init(t.allocator, 3);
    defer df.deinit(t.allocator);

    df.push(.{
        .a = 1,
        .b = "123456",
        .c = 'a',
    });

    df.push(.{
        .a = 2,
        .b = "zigzag",
        .c = 'b',
    });

    var df2 = try df.clone(t.allocator);
    defer df2.deinit(t.allocator);

    try t.expectEqual(df.get(1), df2.get(1));
    try t.expectEqual(df.len, df2.len);
    try t.expectEqual(df.capacity, df2.capacity);
    try t.expectEqualSlices(u8, df.bytes[0..df.capacity], df2.bytes[0..df2.capacity]);
}

test "zero-sized-field" {
    const t = std.testing;
    const X = struct {
        a: u0,
        b: f32,
    };

    var df = try DataFrame(X).init(t.allocator, 3);
    defer df.deinit(t.allocator);

    try t.expectEqualSlices(u0, &[_]u0{}, df.items(.a));
    try t.expectEqualSlices(f32, &[_]f32{}, df.items(.b));

    df.push(.{ .a = 0, .b = 42.0 });
    try t.expectEqualSlices(u0, &[_]u0{0}, df.items(.a));
    try t.expectEqualSlices(f32, &[_]f32{42.0}, df.items(.b));

    df.push(.{ .a = 0, .b = -1.0 });
    try t.expectEqualSlices(u0, &[_]u0{ 0, 0 }, df.items(.a));
    try t.expectEqualSlices(f32, &[_]f32{ 42.0, -1.0 }, df.items(.b));

    df.remove(df.len - 1);
    try t.expectEqualSlices(u0, &[_]u0{0}, df.items(.a));
    try t.expectEqualSlices(f32, &[_]f32{42.0}, df.items(.b));
}

test "zero-sized-struct" {
    const t = std.testing;
    const X = struct {
        a: u0,
    };

    var df = try DataFrame(X).init(t.allocator, 3);
    defer df.deinit(t.allocator);

    try t.expectEqualSlices(u0, &[_]u0{}, df.items(.a));

    df.push(.{ .a = 0 });
    try t.expectEqualSlices(u0, &[_]u0{0}, df.items(.a));

    df.push(.{ .a = 0 });
    try t.expectEqualSlices(u0, &[_]u0{ 0, 0 }, df.items(.a));

    df.remove(df.len - 1);
    try t.expectEqualSlices(u0, &[_]u0{0}, df.items(.a));
}

test "union" {
    const t = std.testing;
    const X = union(enum) {
        a: u32,
        b: []const u8,
    };

    var df = try DataFrame(X).init(t.allocator, 3);
    defer df.deinit(t.allocator);

    try t.expectEqual(@as(usize, 0), df.items(.tags).len);

    df.push(.{ .a = 1 });
    df.push(.{ .b = "zigzag" });

    try t.expectEqualSlices(std.meta.Tag(X), df.items(.tags), &.{ .a, .b });
    try t.expectEqual(@as(usize, 2), df.items(.tags).len);

    df.push(.{ .b = "123456" });
    try t.expectEqualStrings("zigzag", df.items(.data)[1].b);
    try t.expectEqualStrings("123456", df.items(.data)[2].b);

    try t.expectEqualSlices(
        std.meta.Tag(X),
        &.{ .a, .b, .b },
        df.items(.tags),
    );
    try t.expectEqual(X{ .a = 1 }, df.get(0));
    try t.expectEqual(X{ .b = "zigzag" }, df.get(1));
    try t.expectEqual(X{ .b = "123456" }, df.get(2));
}
