const std = @import("std");
const Allocator = std.mem.Allocator;
const RingBuffer = @import("RingBuffer.zig");

pub fn ThreadSafeRingBuffer(comptime T: type) type {
    return struct {
        const Self = @This();
        const Impl = RingBuffer(T);

        mutex: std.Thread.Mutex,
        impl: Impl,

        pub fn init(ally: Allocator, capacity: usize) Allocator.Error!Self {
            return Self{
                .mutex = .{},
                .impl = try Impl.init(ally, capacity),
            };
        }

        pub fn deinit(self: *Self, ally: Allocator) void {
            self.mutex.lock();
            self.impl.deinit(ally);
            self.mutex.unlock();
            self.* = undefined;
        }

        pub fn push(self: *Self, element: T) Impl.Error!void {
            self.mutex.lock();
            defer {
                self.mutex.unlock();
            }
            try self.impl.push(element);
        }

        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer {
                self.mutex.unlock();
            }
            return self.impl.pop();
        }
    };
}
