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
    source: Sources,

    pub fn init(ally: Allocator, sources: Sources, config: Config) Node {
        return .{
            .ally = ally,
            .sources = sources,
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
        const element = front.?;
        const packet = &element.packet;
        const header = &packet.header;

        defer {
            self.ally.free(element.raw_data);
        }

        if (self.shouldDrop(packet)) {
            return;
        }

        _ = now;
        header.hops += 1;

        if (header.endpoint == .plain and header.propagation == .broadcast) {
            self.sender.send(packet);
        }
    }

    fn shouldDrop(self: *Self, packet: *Packet) bool {
        _ = self;
        _ = packet;
        // Ifac flag should match whether we are authenticated, else drop.
        return false;
    }
};
