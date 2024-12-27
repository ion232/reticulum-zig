const std = @import("std");

const Allocator = std.mem.Allocator;
const Endpoint = @import("Endpoint.zig");
const Interface = @import("Interface.zig");
const Config = @import("node/Config.zig");
const Packet = @import("node/Packet.zig");
const RingBuffer = @import("node/RingBuffer.zig").RingBuffer;
const System = @import("System.zig");

const Self = @This();
const InterfaceId = u8;
const Error = error{
    TooManyInterfaces,
    InvalidInterfaceId,
};

ally: Allocator,
system: System,
config: Config,
interfaces: std.ArrayList(?Interface),
incoming: Queue(.in),
outgoing: std.ArrayList(Queue(.out)),

pub fn init(ally: Allocator, system: System, config: Config) Self {
    return .{
        .ally = ally,
        .system = system,
        .config = config,
        .incoming = Queue(.in).init(
            ally,
            config.max_incoming_packets,
        ),
        .outgoing = std.ArrayList(Queue(.out)).init(ally),
    };
}

pub fn process(self: *Self) Error!void {
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

pub fn addInterface(self: *Self, interface: Interface) Error!InterfaceId {
    if (self.interfaces.items.len == self.interfaces.capacity) {
        return Error.TooManyInterfaces;
    }

    for (0.., self.interfaces.items) |id, entry| {
        if (entry == null) {
            entry.* = interface;
            return id;
        }
    }

    self.interfaces.append(interface);

    return self.interfaces.items.len - 1;
}

pub fn removeInterface(self: *Self, id: InterfaceId) Error!void {
    if (id >= self.interfaces.items.len) {
        return Error.InvalidInterfaceId;
    }
    self.interfaces[id] = null;
}

fn shouldDrop(self: *Self, packet: *Packet) bool {
    _ = self;
    _ = packet;
    return false;
}

fn Queue(comptime direction: Endpoint.Direction) type {
    return switch (direction) {
        .in => RingBuffer(Element.In),
        .out => RingBuffer(Element.Out),
    };
}

const Element = struct {
    pub const In = struct {
        packet: Packet,
        interface_id: InterfaceId,
    };
    pub const Out = struct {
        data: []const u8,
    };
};
