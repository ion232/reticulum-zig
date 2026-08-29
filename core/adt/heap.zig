/// Modified from std.priority_queue.PriorityQueue.
const std = @import("std");
const Allocator = std.mem.Allocator;
const t = std.testing;

/// A fixed size heap for use as a priority heap.
/// For a min heap, use e.g. `std.math.order`.
pub fn Heap(comptime T: type, comptime compareFn: fn (a: T, b: T) std.math.Order) type {
    return struct {
        pub const Error = error{ ElementNotFound, Full };

        const Self = @This();

        items: []T,
        capacity: usize,

        pub fn init(allocator: Allocator, capacity: usize) error{OutOfMemory}!Self {
            var items = try allocator.alloc(T, capacity);
            items.len = 0;

            return Self{
                .items = items,
                .capacity = capacity,
            };
        }

        pub fn peek(self: *Self) ?T {
            return if (self.items.len > 0) self.items[0] else null;
        }

        pub fn push(self: *Self, elem: T) Error!void {
            if (self.items.len == self.capacity) return error.Full;

            self.items.len += 1;
            self.items[self.items.len - 1] = elem;
            siftUp(self, self.items.len - 1);
        }

        pub fn pop(self: *Self) ?T {
            if (self.items.len == 0) return null;

            const last = self.items[self.items.len - 1];
            const first = self.items[0];
            self.items[0] = last;
            self.items.len -= 1;

            if (self.items.len > 0) {
                siftDown(self, 0);
            }

            return first;
        }

        pub fn update(self: *Self, elem: T, new_elem: T) error{ElementNotFound}!void {
            const update_index = blk: {
                var idx: usize = 0;
                while (idx < self.items.len) : (idx += 1) {
                    const item = self.items[idx];
                    if (compareFn(item, elem) == .eq) break :blk idx;
                }
                return error.ElementNotFound;
            };
            const old_elem: T = self.items[update_index];
            self.items[update_index] = new_elem;
            switch (compareFn(new_elem, old_elem)) {
                .lt => siftUp(self, update_index),
                .gt => siftDown(self, update_index),
                .eq => {}, // Nothing to do as the items have equal priority
            }
        }

        pub fn count(self: Self) usize {
            return self.items.len;
        }

        pub fn deinit(self: *Self, allocator: Allocator) void {
            self.items.len = self.capacity;
            allocator.free(self.items);
        }

        fn siftUp(self: *Self, start_index: usize) void {
            const child = self.items[start_index];
            var child_index = start_index;
            while (child_index > 0) {
                const parent_index = ((child_index - 1) >> 1);
                const parent = self.items[parent_index];
                if (compareFn(child, parent) != .lt) break;
                self.items[child_index] = parent;
                child_index = parent_index;
            }
            self.items[child_index] = child;
        }

        fn siftDown(self: *Self, target_index: usize) void {
            const target_element = self.items[target_index];
            var index = target_index;
            while (true) {
                var lesser_child_i = (std.math.mul(usize, index, 2) catch break) | 1;
                if (!(lesser_child_i < self.items.len)) break;

                const next_child_i = lesser_child_i + 1;
                if (next_child_i < self.items.len and compareFn(self.items[next_child_i], self.items[lesser_child_i]) == .lt) {
                    lesser_child_i = next_child_i;
                }

                if (compareFn(target_element, self.items[lesser_child_i]) == .lt) break;

                self.items[index] = self.items[lesser_child_i];
                index = lesser_child_i;
            }
            self.items[index] = target_element;
        }
    };
}

fn lt(a: u32, b: u32) std.math.Order {
    return std.math.order(a, b);
}

fn gt(a: u32, b: u32) std.math.Order {
    return lt(a, b).invert();
}

const MinHeap = Heap(u32, lt);
const MaxHeap = Heap(u32, gt);

test "add-and-remove-min-heap" {
    var heap = try MinHeap.init(t.allocator, 6);
    defer heap.deinit(t.allocator);

    try heap.push(54);
    try heap.push(12);
    try heap.push(7);
    try heap.push(23);
    try heap.push(25);
    try heap.push(13);
    try t.expectEqual(@as(u32, 7), heap.pop());
    try t.expectEqual(@as(u32, 12), heap.pop());
    try t.expectEqual(@as(u32, 13), heap.pop());
    try t.expectEqual(@as(u32, 23), heap.pop());
    try t.expectEqual(@as(u32, 25), heap.pop());
    try t.expectEqual(@as(u32, 54), heap.pop());
}

test "add-and-remove-same-min-heap" {
    var heap = try MinHeap.init(t.allocator, 6);
    defer heap.deinit(t.allocator);

    try heap.push(1);
    try heap.push(1);
    try heap.push(2);
    try heap.push(2);
    try heap.push(1);
    try heap.push(1);
    try t.expectEqual(@as(u32, 1), heap.pop());
    try t.expectEqual(@as(u32, 1), heap.pop());
    try t.expectEqual(@as(u32, 1), heap.pop());
    try t.expectEqual(@as(u32, 1), heap.pop());
    try t.expectEqual(@as(u32, 2), heap.pop());
    try t.expectEqual(@as(u32, 2), heap.pop());
}

test "pop-on-empty" {
    var heap = try MinHeap.init(t.allocator, 0);
    defer heap.deinit(t.allocator);

    try t.expect(heap.pop() == null);
}

test "three-elements" {
    var heap = try MinHeap.init(t.allocator, 3);
    defer heap.deinit(t.allocator);

    try heap.push(9);
    try heap.push(3);
    try heap.push(2);
    try t.expectEqual(@as(u32, 2), heap.pop());
    try t.expectEqual(@as(u32, 3), heap.pop());
    try t.expectEqual(@as(u32, 9), heap.pop());
}

test "peek" {
    var heap = try MinHeap.init(t.allocator, 3);
    defer heap.deinit(t.allocator);

    try t.expect(heap.peek() == null);
    try heap.push(9);
    try heap.push(3);
    try heap.push(2);
    try t.expectEqual(@as(u32, 2), heap.peek().?);
    try t.expectEqual(@as(u32, 2), heap.peek().?);
}

test "sift-up-with-odd-indices" {
    var heap = try MinHeap.init(t.allocator, 100);
    defer heap.deinit(t.allocator);

    const items = [_]u32{ 15, 7, 21, 14, 13, 22, 12, 6, 7, 25, 5, 24, 11, 16, 15, 24, 2, 1 };
    for (items) |e| {
        try heap.push(e);
    }

    const sorted_items = [_]u32{ 1, 2, 5, 6, 7, 7, 11, 12, 13, 14, 15, 15, 16, 21, 22, 24, 24, 25 };
    for (sorted_items) |e| {
        try t.expectEqual(e, heap.pop());
    }
}

test "add-and-remove-max-heap" {
    var heap = try MaxHeap.init(t.allocator, 6);
    defer heap.deinit(t.allocator);

    try heap.push(54);
    try heap.push(12);
    try heap.push(7);
    try heap.push(23);
    try heap.push(25);
    try heap.push(13);
    try t.expectEqual(@as(u32, 54), heap.pop());
    try t.expectEqual(@as(u32, 25), heap.pop());
    try t.expectEqual(@as(u32, 23), heap.pop());
    try t.expectEqual(@as(u32, 13), heap.pop());
    try t.expectEqual(@as(u32, 12), heap.pop());
    try t.expectEqual(@as(u32, 7), heap.pop());
}

test "add-and-remove-same-max-heap" {
    var heap = try MaxHeap.init(t.allocator, 6);
    defer heap.deinit(t.allocator);

    try heap.push(1);
    try heap.push(1);
    try heap.push(2);
    try heap.push(2);
    try heap.push(1);
    try heap.push(1);
    try t.expectEqual(@as(u32, 2), heap.pop());
    try t.expectEqual(@as(u32, 2), heap.pop());
    try t.expectEqual(@as(u32, 1), heap.pop());
    try t.expectEqual(@as(u32, 1), heap.pop());
    try t.expectEqual(@as(u32, 1), heap.pop());
    try t.expectEqual(@as(u32, 1), heap.pop());
}

test "update-min-heap" {
    var heap = try MinHeap.init(t.allocator, 3);
    defer heap.deinit(t.allocator);

    try heap.push(55);
    try heap.push(44);
    try heap.push(11);
    try heap.update(55, 5);
    try heap.update(44, 4);
    try heap.update(11, 1);
    try t.expectEqual(@as(u32, 1), heap.pop());
    try t.expectEqual(@as(u32, 4), heap.pop());
    try t.expectEqual(@as(u32, 5), heap.pop());
}

test "update-same-min-heap" {
    var heap = try MinHeap.init(t.allocator, 4);
    defer heap.deinit(t.allocator);

    try heap.push(1);
    try heap.push(1);
    try heap.push(2);
    try heap.push(2);
    try heap.update(1, 5);
    try heap.update(2, 4);
    try t.expectEqual(@as(u32, 1), heap.pop());
    try t.expectEqual(@as(u32, 2), heap.pop());
    try t.expectEqual(@as(u32, 4), heap.pop());
    try t.expectEqual(@as(u32, 5), heap.pop());
}

test "update-max-heap" {
    var heap = try MaxHeap.init(t.allocator, 3);
    defer heap.deinit(t.allocator);

    try heap.push(55);
    try heap.push(44);
    try heap.push(11);
    try heap.update(55, 5);
    try heap.update(44, 1);
    try heap.update(11, 4);
    try t.expectEqual(@as(u32, 5), heap.pop());
    try t.expectEqual(@as(u32, 4), heap.pop());
    try t.expectEqual(@as(u32, 1), heap.pop());
}

test "update-same-max-heap" {
    var heap = try MaxHeap.init(t.allocator, 4);
    defer heap.deinit(t.allocator);

    try heap.push(1);
    try heap.push(1);
    try heap.push(2);
    try heap.push(2);
    try heap.update(1, 5);
    try heap.update(2, 4);
    try t.expectEqual(@as(u32, 5), heap.pop());
    try t.expectEqual(@as(u32, 4), heap.pop());
    try t.expectEqual(@as(u32, 2), heap.pop());
    try t.expectEqual(@as(u32, 1), heap.pop());
}

test "update-after-remove" {
    var heap = try MinHeap.init(t.allocator, 1);
    defer heap.deinit(t.allocator);

    try heap.push(1);
    try t.expectEqual(@as(u32, 1), heap.pop());
    try t.expectError(error.ElementNotFound, heap.update(1, 1));
}
