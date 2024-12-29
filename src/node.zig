const std = @import("std");
const interface = @import("interface.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @import("endpoint.zig").Endpoint;
const EndpointStore = @import("endpoint/Store.zig");
const Hash = @import("crypto.zig").Hash;
const InterfaceEngine = interface.Engine;
const Options = @import("node/Options.zig");
const Packet = @import("node/Packet.zig");
const RingBuffer = @import("internal/RingBuffer.zig").RingBuffer;
const System = @import("System.zig");

const Self = @This();

pub const Error = error{
    InvalidInterfaceId,
    TooManyInterfaces,
    TooManyIncoming,
};

ally: Allocator,
system: System,
options: Options,
endpoint_store: EndpointStore,
interface_engine: InterfaceEngine,
incoming: std.RingBuffer(Element.In),
routes: std.StringHashMap(Hash),

pub fn init(ally: Allocator, system: System, options: Options) Allocator.Error!Self {
    return .{
        .ally = ally,
        .system = system,
        .options = options,
        .incoming = try Queue(.in).init(ally, options.max_incoming_packets),
        .outgoing = std.ArrayList(?Queue(.out)).init(ally),
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

pub fn push(self: *Self, id: interface.Id, packet: Packet) !void {
    try self.incoming.push(.{
        .packet = packet,
        .id = id,
    });
}

pub fn pop(self: *Self, id: interface.Id) Error!?[]const u8 {
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
        id: interface.Id,
        packet: Packet,
    };
    const Out = struct {
        data: []const u8,
    };
};
