const std = @import("std");
const crypto = @import("crypto/crypto.zig");
const endpoint = @import("endpoint/endpoint.zig");

const Allocator = std.mem.Allocator;
const Sources = @import("sources.zig").Sources;

const Interface = @import("interface/interface.zig").Interface;
const Packet = u8;
const PacketQueue = std.PriorityQueue(Packet, void, compare_packets);

pub const Node = struct {
    const Self = @This();

    ally: Allocator,
    sources: Sources,
    receive_queue: PacketQueue,
    send_queue: PacketQueue,

    pub fn init(ally: Allocator, sources: Sources) Node {
        return .{
            .ally = ally,
            .sources = sources,
            .receive_queue = PacketQueue.init(ally, void),
            .send_queue = PacketQueue.init(ally, void),
        };
    }

    pub fn process(self: *Self) !void {
        const packet = self.receive_queue.peek();
        if (packet == null) {
            return;
        }

        try process_packet(packet);
    }

    fn process_packet(self: *Self, packet: Packet) !void {}

    fn send(self: *Self, packet: Packet) !void {
        try self.send_queue.add(packet);
    }
};

fn compare_packets(context: void, a: Packet, b: Packet) std.math.Order {
    _ = context;
    return std.math.order(a, b);
}
