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
const ThreadSafeFifo = @import("internal/ThreadSafeFifo.zig").ThreadSafeFifo;
const System = @import("System.zig");

pub const Error = error{
    InterfaceNotFound,
    TooManyInterfaces,
    TooManyIncoming,
} || Allocator.Error;

const Route = struct {
    timestamp: u64,
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
    incoming.* = try interface.Engine.Incoming.init(self.ally);
    outgoing.* = try interface.Engine.Outgoing.init(self.ally);
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

pub fn process(self: *Self) !void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    const now = self.system.clock.monotonicNanos();
    try self.process_incoming(now);
    try self.process_outgoing(now);
}

fn process_incoming(self: *Self, now: u64) !void {
    var iterator = self.interfaces.iterator();

    while (iterator.next()) |entry| {
        var incoming = entry.value_ptr.*.incoming;
        while (incoming.pop()) |element| {
            std.debug.print("incoming packet\n", .{});
            var packet = element.packet;
            var header = packet.header;
            // defer {
            //     self.ally.free(element.packet.deinit());
            // }

            if (self.shouldDrop(&packet)) {
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

                try self.routes.put(&endpoint_hash, Route{
                    .timestamp = now,
                    .interface_id = entry.key_ptr.*,
                    .next_hop = next_hop,
                    .hops = header.hops,
                });
            }
        }
    }
}

fn process_outgoing(self: *Self, now: u64) !void {
    var iterator = self.interfaces.iterator();
    _ = now;

    while (iterator.next()) |entry| {
        var outgoing = entry.value_ptr.*.outgoing;
        while (outgoing.pop()) |element| {
            var packet = element.packet;
            const endpoint = packet.endpoints.endpoint();

            if (packet.header.purpose == .announce) {
                // Broadcast to all interfaces.
                // var interfaces = self.interfaces.valueIterator();
                // while (interfaces.next()) |ife| {
                //     try ife.*.outgoing.push(.{ .packet = packet });
                // }
                // std.debug.print("Got an announce!\n", .{});
                return;
            }

            const route = self.routes.get(&endpoint) orelse return;
            if (route.hops == 1) {
                if (self.interfaces.get(entry.key_ptr.*)) |engine| {
                    try engine.outgoing.push(.{ .packet = packet });
                }
            } else {
                // Modify the packet for transport.
            }
        }
    }
}

fn shouldDrop(self: *Self, packet: *const Packet) bool {
    _ = self;
    _ = packet;
    return false;
}
