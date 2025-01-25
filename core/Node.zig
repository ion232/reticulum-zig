const std = @import("std");

pub const Element = @import("node/Element.zig");
pub const Options = @import("node/Options.zig");

const Allocator = std.mem.Allocator;
const BitRate = @import("unit.zig").BitRate;
const Endpoint = @import("endpoint.zig").Managed;
const EndpointStore = @import("endpoint/Store.zig");
const Hash = @import("crypto.zig").Hash;
const Interface = @import("Interface.zig");
const Identity = @import("crypto.zig").Identity;
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
    interface_id: Interface.Id,
    next_hop: Hash.Short,
    hops: u8,
};

const Self = @This();

ally: Allocator,
system: System,
options: Options,
mutex: std.Thread.Mutex,
endpoints: EndpointStore,
interfaces: std.AutoHashMap(Interface.Id, *Interface),
routes: std.StringHashMap(Route),
identity: Identity,
current_interface_id: Interface.Id,

pub fn init(ally: Allocator, system: System, options: Options) Allocator.Error!Self {
    return .{
        .ally = ally,
        .system = system,
        .options = options,
        .mutex = .{},
        .endpoints = EndpointStore.init(ally),
        .interfaces = std.AutoHashMap(Interface.Id, *Interface).init(ally),
        .routes = std.StringHashMap(Route).init(ally),
        // Obviously this needs sorting.
        // Identity should probably be passed in and made with rng if null.
        .identity = undefined,
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
    self.routes.deinit();
}

pub fn addInterface(self: *Self, config: Interface.Config) Error!Interface.Api {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    if (self.interfaces.count() > self.options.max_interfaces) {
        return Error.TooManyInterfaces;
    }

    const id = self.current_interface_id;
    self.current_interface_id += 1;

    const incoming = try self.ally.create(Interface.Incoming);
    incoming.* = Interface.Incoming.init(self.ally);

    errdefer {
        self.ally.destroy(incoming);
    }

    const outgoing = try self.ally.create(Interface.Outgoing);
    outgoing.* = Interface.Outgoing.init(self.ally);

    errdefer {
        self.ally.destroy(outgoing);
    }

    const packet_factory = PacketFactory.init(
        self.ally,
        self.system.clock,
        self.system.rng,
        config,
    );

    const interface = try self.ally.create(Interface);

    errdefer {
        self.ally.destroy(interface);
    }

    interface.* = Interface.init(
        self.ally,
        config,
        id,
        incoming,
        outgoing,
        packet_factory,
    );

    try self.interfaces.put(id, interface);

    return interface.api();
}

pub fn removeInterface(self: *Self, id: Interface.Id) Error!void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    if (self.interfaces.get(id)) |interface| {
        interface.deinit(self.ally);
        self.ally.destroy(interface);
        return;
    }

    return Error.InterfaceNotFound;
}

pub fn process(self: *Self) !void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    const now = self.system.clock.monotonicMicros();
    var interfaces = self.interfaces.iterator();

    while (interfaces.next()) |e| {
        const interface = e.value_ptr.*;
        try self.processIncoming(now, interface);
    }

    interfaces = self.interfaces.iterator();

    while (interfaces.next()) |e| {
        const interface = e.value_ptr.*;
        try self.processOutgoing(now, interface);
    }
}

fn processIncoming(self: *Self, now: u64, interface: *Interface) !void {
    while (interface.incoming.pop()) |element| {
        var packet = element.packet;
        const header = packet.header;

        if (shouldDrop(&packet)) {
            return;
        }

        try packet.validate();

        if (shouldRemember(&packet)) {
            // Add packet hash to set.
        }

        try self.processTransport(now, &packet);

        try switch (header.purpose) {
            .announce => self.processAnnounce(now, interface, packet),
            .data => self.processData(now, packet),
            .link_request => self.processLinkRequest(now, packet),
            .proof => self.processProof(now, packet),
        };
    }
}

fn processOutgoing(self: *Self, now: u64, interface: *Interface) !void {
    while (interface.outgoing.pop()) |element| {
        var packet = element.packet;
        const endpoint = packet.endpoints.endpoint();
        _ = endpoint;

        if (packet.header.purpose == .announce) {
            var interfaces = self.interfaces.valueIterator();
            while (interfaces.next()) |other_interface| {
                if (other_interface.* != interface) {
                    try other_interface.*.outgoing.push(.{
                        .packet = packet,
                    });
                }
            }
            return;
        }

        // Transmit if interface has outgoing functionality.

        // If transmitting:
        // Emit an announce event for announces.
        // Put into transport if we know where it's going.
        // Otherwise broadcast.
        // Store the packet hash.
    }

    _ = now;
}

fn processTransport(self: *Self, now: u64, packet: *Packet) !void {
    _ = now;

    if (!self.options.transport_enabled) {
        return;
    }

    if (packet.endpoints == .transport and packet.header.purpose != .announce) {
        const next_hop = packet.endpoints.nextHop();
        const our_hash = self.identity.hash.short();
        const next_hop_is_us = std.mem.eql(u8, &next_hop, our_hash);

        if (next_hop_is_us) {
            const endpoint = packet.endpoints.endpoint();

            if (self.routes.get(&endpoint)) |route| {
                switch (route.hops) {
                    0 => {
                        packet.header.hops += 1;
                    },
                    1 => {
                        packet.endpoints = .{ .normal = .{ .endpoint = endpoint } };
                        packet.header.format = .normal;
                        packet.header.propagation = .broadcast;
                    },
                    else => {
                        packet.header.hops += 1;
                        packet.endpoints.transport.transport_id = next_hop;
                    },
                }

                if (packet.header.purpose == .link_request) {
                    // Link request stuff.
                } else {
                    // Add to reverse table [if_in, if_out, timestamp].
                }

                // Transmit.
                // Update endpoint timestamp in table.
            }
        }
    }
}

fn processAnnounce(self: *Self, now: u64, interface: *Interface, packet: Packet) !void {
    const endpoint_hash = packet.endpoints.endpoint();
    const next_hop = packet.endpoints.nextHop();

    try self.routes.put(&endpoint_hash, Route{
        .timestamp = now,
        .interface_id = interface.id,
        .next_hop = next_hop,
        .hops = packet.header.hops,
    });
}

fn processData(self: *Self, now: u64, packet: Packet) !void {
    _ = self;
    _ = now;
    _ = packet;
}

fn processLinkRequest(self: *Self, now: u64, packet: Packet) !void {
    _ = self;
    _ = now;
    _ = packet;
}

fn processProof(self: *Self, now: u64, packet: Packet) !void {
    _ = self;
    _ = now;
    _ = packet;
}

fn shouldDrop(packet: *const Packet) bool {
    _ = packet;
    return false;
}

fn shouldRemember(packet: *const Packet) bool {
    _ = packet;
    return true;
}
