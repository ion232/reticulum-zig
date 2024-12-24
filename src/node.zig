const std = @import("std");
const crypto = @import("crypto/crypto.zig");
const endpoint = @import("endpoint/endpoint.zig");

const Allocator = std.mem.Allocator;
const Sources = @import("sources.zig").Sources;
const Packet = @import("packet.zig").Packet;

const Interface = @import("interface/interface.zig").Interface;

pub const Node = struct {
    const Self = @This();

    ally: Allocator,
    receiver: Receiver,
    sender: Sender,
    config: Config,

    pub fn init(ally: Allocator, config: Config) Node {
        return .{
            .ally = ally,
            .config = config,
            .receiver = Receiver.init(ally),
            .sender = Sender.init(ally),
        };
    }

    pub fn process(self: *Self) !void {
        const front = self.receiver.queue.peek();

        if (front == null) {
            return;
        }

        const now = self.config.sources.clock.monotonicTime();
        _ = now;

        const element = front.?;
        const packet = &element.packet;
        const header = &packet.header;

        defer {
            self.ally.free(element.raw_data);
        }

        if (self.should_drop(packet)) {
            return;
        }

        header.hops += 1;

        if (header.endpoint == .plain and header.propagation == .broadcast) {
            self.sender.send(packet);
        }
    }

    fn should_drop(self: *Self, packet: *Packet) bool {
        _ = self;
        _ = packet;
        return false;
    }
};

const Config = struct {
    sources: Sources,
};

const Receiver = struct {
    const Self = @This();
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

    fn compare(context: void, a: Element, b: Element) std.math.Order {
        _ = context;
        return std.math.order(a, b);
    }
};

const Sender = struct {
    const Self = @This();
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
