const std = @import("std");

const Allocator = std.mem.Allocator;
const Endpoint = @import("endpoint.zig").Endpoint;
const EndpointStore = @import("endpoint/Store.zig");
const Interface = @import("Interface.zig");
const Hash = @import("crypto.zig").Hash;
const Config = @import("node/Config.zig");
const Packet = @import("node/Packet.zig");
const RingBuffer = @import("node/RingBuffer.zig").RingBuffer;
const System = @import("System.zig");

const Self = @This();

pub const Error = error{
    InvalidInterfaceId,
    TooManyInterfaces,
    TooManyIncoming,
};

ally: Allocator,
system: System,
config: Config,
endpoint_store: EndpointStore,
interfaces: std.ArrayList(?Interface),
incoming: Queue(.in),
outgoing: std.ArrayList(?Queue(.out)),
routes: std.StringHashMap(Hash),

pub fn init(ally: Allocator, system: System, config: Config) Allocator.Error!Self {
    return .{
        .ally = ally,
        .system = system,
        .config = config,
        .incoming = try Queue(.in).init(ally, config.max_incoming_packets),
        .outgoing = std.ArrayList(Queue(.out)).init(ally),
    };
}

pub fn deinit(self: *Self) void {
    self.interfaces.deinit();
    self.incoming.deinit(self.ally);
    self.outgoing.deinit();
    self.* = undefined;
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

pub fn push(self: *Self, id: Interface.Id, packet: Packet) !void {
    try self.incoming.push(.{
        .packet = packet,
        .id = id,
    });
}

pub fn pop(self: *Self, id: Interface.Id) Error!?[]const u8 {
    if (self.interfaces.items.len >= id) {
        return Error.InvalidInterfaceId;
    }

    if (self.outgoing.items[id]) |queue| {
        if (queue.pop()) |element| {
            return element.data;
        } else {
            return null;
        }
    }

    return Error.InvalidInterfaceId;
}

pub fn addInterface(self: *Self, interface: Interface) Error!Interface.Id {
    if (self.interfaces.items.len == self.interfaces.capacity) {
        return Error.TooManyInterfaces;
    }

    const queue = Queue(.out).init(
        self.ally,
        self.config.max_outgoing_packets,
    );

    for (0.., self.interfaces.items) |id, *entry| {
        if (entry.* == null) {
            entry.* = interface;
            self.outgoing.items[id] = queue;
            return id;
        }
    }

    const id = self.interfaces.items.len;
    try self.interfaces.append(interface);
    try self.outgoing.append(queue);

    return id;
}

pub fn removeInterface(self: *Self, id: Interface.Id) Error!void {
    if (id >= self.interfaces.items.len or id >= self.outgoing.items.len) {
        return Error.InvalidInterfaceId;
    }
    self.interfaces[id] = null;
    self.outgoing[id].deinit();
    self.outgoing[id] = null;
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
    const In = struct {
        packet: Packet,
        id: Interface.Id,
    };
    const Out = struct {
        data: []const u8,
    };
};
