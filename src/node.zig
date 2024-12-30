const std = @import("std");
const interface = @import("interface.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @import("endpoint.zig").Managed;
const EndpointStore = @import("endpoint/Store.zig");
const Hash = @import("crypto.zig").Hash;
const Options = @import("node/Options.zig");
const Packet = @import("packet.zig").Packet;
const RingBuffer = @import("internal/RingBuffer.zig").RingBuffer;
const System = @import("System.zig");

const Self = @This();

pub const Error = error{
    InterfaceNotFound,
    TooManyInterfaces,
    TooManyIncoming,
} || Allocator.Error;

ally: Allocator,
system: System,
options: Options,
mutex: std.Thread.Mutex,
endpoints: EndpointStore,
interfaces: std.AutoHashMap(interface.Id, *interface.Engine),
incoming: RingBuffer(Element.In),
outgoing: RingBuffer(Element.Out),
routes: std.StringHashMap(Route),
current_interface_id: interface.Id,

pub fn init(ally: Allocator, system: System, options: Options) Allocator.Error!Self {
    return .{
        .ally = ally,
        .system = system,
        .options = options,
        .mutex = .{},
        .endpoints = EndpointStore.init(ally),
        .interfaces = std.AutoHashMap(interface.Id, *interface.Engine).init(ally),
        .incoming = try RingBuffer(Element.In).init(ally, options.max_incoming_packets),
        .outgoing = try RingBuffer(Element.In).init(ally, options.max_outgoing_packets),
        .routes = std.StringHashMap(Hash).init(ally),
        .current_interface_id = 0,
    };
}

pub fn deinit(self: *Self) void {
    self.endpoints.deinit();
    self.interfaces.deinit();
    self.incoming.deinit(self.ally);
    self.outgoing.deinit(self.ally);
    self.routes.deinit();
    self.* = undefined;
}

pub fn addInterface(self: *Self, config: interface.Config) Error!*interface.Engine {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    if (self.interface_engines.count() > self.options.max_interfaces) {
        return Error.TooManyInterfaces;
    }

    const engine = try self.ally.create(interface.Engine);
    engine.* = interface.Engine.init(self.ally, config);

    try self.interface_engines.put(self.current_interface_id, engine);
    self.current_interface_id += 1;

    return engine;
}

pub fn removeInterface(self: *Self, id: interface.Id) Error!void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    if (self.interface_engines.get(id)) |engine| {
        engine.clear();
        self.ally.destroy(engine);
        return;
    }

    return Error.InterfaceNotFound;
}

pub fn process(self: *Self) Error!void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    const now = self.system.clock.monotonicTime();
    self.process_incoming(now);
    self.process_outgoing(now);
}

fn process_incoming(self: *Self, now: i64) !void {
    const front = self.incoming.pop();
    if (front == null) {
        return;
    }

    const element = front.?;
    const packet = &element.packet;
    const header = &packet.header;

    defer {
        self.ally.free(element.raw_data);
    }

    if (self.shouldDrop(packet)) {
        return;
    }

    header.hops += 1;

    var is_valid = try packet.validate();
    if (!is_valid) {
        return;
    }

    if (header.purpose == .announce) {
        const endpoint_hash = packet.endpoints.endpoint();
        const next_hop = packet.endpoints.next_hop();

        // TODO: Check for hash collisions I suppose.
        // TODO: Remember packet.
        // TODO: Remember ratchet.

        try self.routes.put(endpoint_hash, Route{
            .next_hop = next_hop,
            .interface_id = element.interface_id,
            .timestamp = now,
        });
    }
}

fn process_outgoing(self: *Self, now: i64) !void {
    const front = self.outgoing.pop();
    if (front == null) {
        return;
    }

    const element = front.?;
    const packet = &element.packet;
    _ = now;

    const next_hop = packet.endpoints.next_hop();

    if (self.interfaces.get(element.interface_id)) |engine| {
        engine.
    }
}

pub fn receive(self: *Self, id: interface.Id, packet: Packet) !void {
    // Could replace this by using a thread safe queue.
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    try self.incoming.push(.{
        .packet = packet,
        .id = id,
    });
}

pub fn send(self: *Self, id: interface.Id, packet: Packet) !void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    // TODO: Processing code.

    if (self.interface_engines.get(id)) |engine| {
        engine.send(.{ .single = id }, packet);
    }
}

fn shouldDrop(self: *Self, packet: *Packet) bool {
    _ = self;
    _ = packet;
    return false;
}

const Route = struct {
    next_hop: Hash,
    interface_id: interface.Id,
    timestamp: i64,
    // More fields.
};

const Element = struct {
    const In = struct {
        interface_id: interface.Id,
        packet: Packet,
    };
    const Out = struct {
        interface_id: interface.Id,
        packet: Packet,
    };
};
