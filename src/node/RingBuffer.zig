const std = @import("std");
const Allocator = std.mem.Allocator;

fn RingBuffer(comptime T: type) type {
    return struct {
        const Error = error{
            Full,
            Empty,
        };

        const Self = @This();

        ring_buffer: std.RingBuffer,

        pub fn init(ally: Allocator, capacity: usize) Allocator.Error!Self {
            return Self{
                .ring_buffer = try std.RingBuffer.init(
                    ally,
                    capacity * @sizeOf(T),
                ),
            };
        }

        pub fn deinit(self: *Self, ally: Allocator) void {
            ally.free(self.data);
            self.* = undefined;
        }

        pub fn push(self: *Self, element: T) Error!void {
            try self.ring_buffer.writeSlice(std.mem.bytesAsSlice(u8, element));
        }

        pub fn pop(self: *Self) ?T {
            const element: T = undefined;
            self.ring_buffer.readFirst(std.mem.asBytes(&element), @sizeOf(T)) catch return null;
            return element;
        }
    };
}
