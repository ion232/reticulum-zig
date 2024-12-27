const std = @import("std");
const crypto = @import("crypto/crypto.zig");
const endpoint = @import("endpoint/endpoint.zig");

const Allocator = std.mem.Allocator;
const Config = @import("node/Config.zig");
const System = @import("System.zig");
const Packet = @import("node/Packet.zig");
const Queue = @import("queue.zig").Queue;

const Interface = @import("interface/interface.zig").Interface;

pub const Node = struct {
    const Self = @This();
    const InterfaceId = u8;

    ally: Allocator,
    system: System,
    config: Config,
    incoming: Queue(.in),
    outgoing: [InterfaceId]Queue(.out),

    pub fn init(ally: Allocator, system: System, config: Config) Node {
        return .{
            .ally = ally,
            .system = system,
            .config = config,
            .receiver = Receiver.init(ally),
            .sender = Sender.init(ally),
        };
    }

    pub fn add_interface(interface: *const Interface) InterfaceId {}

    pub fn remove_interface() InterfaceId {}

    pub fn process(self: *Self) !void {
        const front = self.receiver.queue.peek();

        if (front == null) {
            return;
        }

        const now = self.system.clock.monotonicTime();
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
