const std = @import("std");
const interface = @import("interface.zig");

const Allocator = std.mem.Allocator;
const BitRate = @import("units.zig").BitRate;
const Element = @import("node/Element.zig");
const Endpoint = @import("endpoint.zig").Managed;
const EndpointStore = @import("endpoint/Store.zig");
const Hash = @import("crypto.zig").Hash;
const Hooks = @import("node/Hooks.zig");
const Options = @import("node/Options.zig");
const Packet = @import("packet.zig").Packet;
const RingBuffer = @import("internal/RingBuffer.zig").RingBuffer;
const ThreadSafeRingBuffer = @import("internal/ThreadSafeRingBuffer.zig").ThreadSafeRingBuffer;
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
incoming: ThreadSafeRingBuffer(Element.In),
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

pub fn addInterface(self: *Self, config: interface.Config) Error!Hooks {
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
    const element = self.incoming.pop() orelse return;
    const packet = &element.packet;
    const header = &packet.header;

    defer {
        self.ally.free(element.raw_data);
    }

    if (self.shouldDrop(packet)) {
        return;
    }

    header.hops += 1;

    const is_valid = try packet.validate();
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
            .timestamp = now,
            .interface_id = element.interface_id,
            .next_hop = next_hop,
            .hops = header.hops,
        });
    }
}

fn process_outgoing(self: *Self, now: i64) !void {
    const element = self.outgoing.pop() orelse return;
    const packet = element.packet;
    _ = now;

    const endpoint = packet.endpoints.endpoint();

    if (packet.header.purpose == .announce) {
        // Broadcast to all interfaces.
        return;
    }

    const route = self.routes.get(endpoint) orelse return;
    if (route.hops == 1) {
        if (self.interfaces.get(element.interface_id)) |engine| {
            engine.send(packet);
        }
    } else {
        // Modify the packet for transport.
    }
}

pub fn receive(self: *Self, id: interface.Id, packet: Packet) !void {
    try self.incoming.push(.{
        .id = id,
        .packet = packet,
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
    timestamp: i64,
    interface_id: interface.Id,
    next_hop: Hash.Short,
    hops: u8,
    // More fields.
};
