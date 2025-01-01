const std = @import("std");
const interface = @import("interface.zig");

pub const Element = @import("node/Element.zig");
pub const Options = @import("node/Options.zig");

const Allocator = std.mem.Allocator;
const BitRate = @import("units.zig").BitRate;
const Endpoint = @import("endpoint.zig").Managed;
const EndpointStore = @import("endpoint/Store.zig");
const Hash = @import("crypto.zig").Hash;
const Packet = @import("packet.zig").Packet;
const PacketFactory = @import("packet.zig").Factory;
const RingBuffer = @import("internal/RingBuffer.zig").RingBuffer;
const ThreadSafeRingBuffer = @import("internal/ThreadSafeRingBuffer.zig").ThreadSafeRingBuffer;
const System = @import("System.zig");

pub const Error = error{
    InterfaceNotFound,
    TooManyInterfaces,
    TooManyIncoming,
} || Allocator.Error;

const Route = struct {
    timestamp: i64,
    interface_id: interface.Id,
    next_hop: Hash.Short,
    hops: u8,
    // More fields.
};

const Self = @This();

ally: Allocator,
system: System,
options: Options,
mutex: std.Thread.Mutex,
endpoints: EndpointStore,
interfaces: std.AutoHashMap(interface.Id, *interface.Engine),
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
        .routes = std.StringHashMap(Route).init(ally),
        .current_interface_id = 0,
    };
}

pub fn deinit(self: *Self) void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
        self.* = undefined;
    }

    self.endpoints.deinit();
    self.interfaces.deinit();
    self.incoming.deinit(self.ally);
    self.outgoing.deinit(self.ally);
    self.routes.deinit();
}

pub fn addInterface(self: *Self, config: interface.Config) Error!interface.Engine.Api {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    if (self.interfaces.count() > self.options.max_interfaces) {
        return Error.TooManyInterfaces;
    }

    const id = self.current_interface_id;
    self.current_interface_id += 1;

    const incoming = try self.ally.create(interface.Engine.Incoming);
    const outgoing = try self.ally.create(interface.Engine.Outgoing);
    incoming.* = try interface.Engine.Incoming.init(self.ally, config.max_held_packets);
    outgoing.* = try interface.Engine.Outgoing.init(self.ally, config.max_held_packets);
    const packet_factory = PacketFactory.init(self.ally, self.system.clock, self.system.rng, config);

    const engine = try self.ally.create(interface.Engine);
    engine.* = try interface.Engine.init(self.ally, config, id, incoming, outgoing, packet_factory);
    try self.interfaces.put(id, engine);

    return engine.api();
}

pub fn removeInterface(self: *Self, id: interface.Id) Error!void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    if (self.interfaces.get(id)) |engine| {
        engine.deinit(self.ally);
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

    const now = self.system.clock.monotonicNanos();
    try self.process_incoming(now);
    try self.process_outgoing(now);
}

fn process_incoming(self: *Self, now: u64) !void {
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

fn process_outgoing(self: *Self, now: u64) !void {
    const element = self.outgoing.pop() orelse return;
    const packet = element.packet;
    _ = now;

    const endpoint = packet.endpoints.endpoint();

    if (packet.header.purpose == .announce) {
        // Broadcast to all interfaces.
        // const interfaces = self.interfaces.valueIterator();
        // while (interfaces.next()) |interface| {}
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

fn shouldDrop(self: *Self, packet: *Packet) bool {
    _ = self;
    _ = packet;
    return false;
}
