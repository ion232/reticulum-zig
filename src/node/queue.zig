const std = @import("std");

pub const Direction = enum {
    in,
    out,
};

pub fn Queue(comptime direction: Direction) type {
    return switch (direction) {
        .in => In,
        .out => Out,
    };
}

pub const In = struct {
    const Self = @This();
    // ion232: Replace this with a purpose built queue. Possibly lock free spsc but more likely mutex protected.
    const Queue = std.PriorityQueue(Element, void, compare);
    const Element = struct {
        packet: Packet,
        raw_data: []u8,
    };

    queue: Queue,

    fn init(ally: Allocator) Receiver {
        return .{
            .queue = Queue.init(ally, void),
        };
    }

    fn receive() void {}

    fn compare(context: void, a: Element, b: Element) std.math.Order {
        _ = context;
        return std.math.order(a, b);
    }
};

pub const Out = struct {
    const Self = @This();
    // ion232: Replace this with a purpose built queue. Possibly lock free spsc but more likely mutex protected.
    const Queue = std.PriorityQueue(Element, void, compare);
    const Element = struct {
        data: []const u8,
    };

    queue: Queue,

    fn init(ally: Allocator) Sender {
        return .{
            .queue = Queue.init(ally, void),
        };
    }

    fn send(self: *Self, packet: *Packet) !void {
        const buffer = self.ally.alloc(u8, packet.size());
        try packet.write(buffer);
        try self.queue.add(.{
            .data = buffer,
        });

        return;
    }

    fn compare() std.math.Order {
        return std.math.Order.eq;
    }
};
