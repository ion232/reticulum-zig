/// Modified from std.heap.MemoryPool.
const std = @import("std");
const t = std.testing;

const Allocator = std.mem.Allocator;

/// A fixed size memory pool.
pub fn Pool(comptime T: type) type {
    const Node = struct { next: ?*@This() };

    std.debug.assert(@alignOf(T) >= @alignOf(Node));
    std.debug.assert(@sizeOf(T) >= @sizeOf(Node));

    return struct {
        const Self = @This();

        buffer: []T,
        free_list: ?*Node = null,

        pub fn init(allocator: Allocator, capacity: usize) error{OutOfMemory}!Self {
            std.debug.assert(capacity >= 1);

            var pool = Self{
                .buffer = try allocator.alloc(T, capacity),
                .free_list = null,
            };

            for (0..capacity) |i| {
                const node = @as(*Node, @ptrCast(pool.buffer.ptr + i));
                node.* = Node{ .next = pool.free_list };
                pool.free_list = node;
            }

            return pool;
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            allocator.free(self.buffer);
            self.* = undefined;
        }

        pub fn create(self: *Self) error{OutOfMemory}!*T {
            const node = self.free_list orelse return error.OutOfMemory;
            self.free_list = node.next;

            const ptr = @as(*T, @ptrCast(node));
            ptr.* = undefined;

            return ptr;
        }

        pub fn destroy(self: *Self, ptr: *T) void {
            ptr.* = undefined;

            const node: *Node = @ptrCast(ptr);
            node.* = Node{ .next = self.free_list };
            self.free_list = node;
        }
    };
}

test "u64" {
    var pool = try Pool(u64).init(t.allocator, 3);
    defer pool.deinit(t.allocator);

    const p1 = try pool.create();
    const p2 = try pool.create();
    const p3 = try pool.create();

    try t.expect(p1 != p2);
    try t.expect(p1 != p3);
    try t.expect(p2 != p3);

    pool.destroy(p2);

    const p4 = try pool.create();
    p4.* = 42;

    try t.expect(p2 == p4);
    try t.expectError(error.OutOfMemory, pool.create());
}

test "struct" {
    const X = struct {
        a: u64,
    };

    var pool = try Pool(X).init(t.allocator, 3);
    defer pool.deinit(t.allocator);

    const p1 = try pool.create();
    const p2 = try pool.create();
    const p3 = try pool.create();

    try t.expect(p1 != p2);
    try t.expect(p1 != p3);
    try t.expect(p2 != p3);

    pool.destroy(p2);

    const p4 = try pool.create();
    p4.* = .{
        .a = 42,
    };

    try t.expect(p2 == p4);
    try t.expectError(error.OutOfMemory, pool.create());
}

test "empty-and-fill" {
    const Y = struct {
        b: u64,
        c: u1,
        d: i5,
        e: []const u8,
    };

    var pool = try Pool(Y).init(t.allocator, 3);
    defer pool.deinit(t.allocator);

    const p1 = try pool.create();
    const p2 = try pool.create();
    const p3 = try pool.create();

    pool.destroy(p1);
    pool.destroy(p2);
    pool.destroy(p3);

    const p4 = try pool.create();
    const p5 = try pool.create();
    const p6 = try pool.create();

    try t.expectEqual(p3, p4);
    try t.expectEqual(p2, p5);
    try t.expectEqual(p1, p6);

    pool.destroy(p2);
    pool.destroy(p3);
    pool.destroy(p1);

    const p7 = try pool.create();
    const p8 = try pool.create();
    const p9 = try pool.create();

    try t.expectEqual(p1, p7);
    try t.expectEqual(p3, p8);
    try t.expectEqual(p2, p9);
}
