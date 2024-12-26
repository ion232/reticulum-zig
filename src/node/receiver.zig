const std = @import("std");

const Receiver = struct {
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
