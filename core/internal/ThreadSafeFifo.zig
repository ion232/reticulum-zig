const std = @import("std");
const Allocator = std.mem.Allocator;

pub fn ThreadSafeFifo(comptime T: type) type {
    return struct {
        pub const Error = Allocator.Error;

        const Self = @This();
        const Impl = std.PriorityQueue(T, void, compare);

        mutex: std.Thread.Mutex,
        impl: Impl,

        pub fn init(ally: Allocator) Self {
            return Self{
                .mutex = .{},
                .impl = .init(ally, {}),
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            self.impl.deinit();
            self.mutex.unlock();
        }

        pub fn push(self: *Self, element: T) Error!void {
            self.mutex.lock();
            defer self.mutex.unlock();
            try self.impl.add(element);
        }

        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.impl.removeOrNull();
        }

        fn compare(_: void, _: T, _: T) std.math.Order {
            return .eq;
        }
    };
}
