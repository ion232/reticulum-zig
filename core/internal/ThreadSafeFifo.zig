const std = @import("std");
const Allocator = std.mem.Allocator;
const LinearFifo = std.fifo.LinearFifo;

pub fn ThreadSafeFifo(comptime T: type) type {
    return struct {
        pub const Error = Allocator.Error;

        const Self = @This();
        const Impl = LinearFifo(T, .Dynamic);

        mutex: std.Thread.Mutex,
        impl: Impl,

        pub fn init(ally: Allocator) Self {
            return Self{
                .mutex = .{},
                .impl = Impl.init(ally),
            };
        }

        pub fn deinit(self: *Self) void {
            self.mutex.lock();
            self.impl.deinit();
            self.mutex.unlock();
            self.* = undefined;
        }

        pub fn push(self: *Self, element: T) Error!void {
            self.mutex.lock();
            defer {
                self.mutex.unlock();
            }
            try self.impl.writeItem(element);
        }

        pub fn pop(self: *Self) ?T {
            self.mutex.lock();
            defer {
                self.mutex.unlock();
            }
            return self.impl.readItem();
        }
    };
}
