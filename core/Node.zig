const std = @import("std");

pub const Event = @import("node/Event.zig");
pub const Options = @import("node/Options.zig");

const Allocator = std.mem.Allocator;
const BitRate = @import("unit.zig").BitRate;
const Endpoint = @import("endpoint.zig").Managed;
const EndpointBuilder = @import("endpoint.zig").Builder;
const Endpoints = @import("endpoint/Store.zig");
const Hash = @import("crypto.zig").Hash;
const Interface = @import("Interface.zig");
const Interfaces = @import("interface/Manager.zig");
const Identity = @import("crypto.zig").Identity;
const Packet = @import("packet.zig").Packet;
const PacketFactory = @import("packet.zig").Factory;
const Routes = @import("Routes.zig");
const Name = @import("endpoint/Name.zig");
const ThreadSafeFifo = @import("internal/ThreadSafeFifo.zig").ThreadSafeFifo;
const System = @import("System.zig");

pub const Error = Interfaces.Error || Identity.Error || EndpointBuilder.Error || Name.Error || Allocator.Error;

const Self = @This();

ally: Allocator,
mutex: std.Thread.Mutex,
system: System,
options: Options,
endpoints: Endpoints,
interfaces: Interfaces,
routes: Routes,

pub fn init(ally: Allocator, system: *System, identity: ?Identity, options: Options) Error!Self {
    var endpoint_builder = EndpointBuilder.init(ally);
    const main_endpoint = try endpoint_builder
        .setIdentity(identity orelse try Identity.random(&system.rng))
        .setDirection(.in)
        .setMethod(.single)
        .setName(try Name.init(options.name, &.{}, ally))
        .build();
    const endpoints = try Endpoints.init(ally, main_endpoint);
    const interfaces = Interfaces.init(ally, system.*);
    const routes = Routes.init(ally);

    return .{
        .ally = ally,
        .mutex = .{},
        .system = system.*,
        .options = options,
        .endpoints = endpoints,
        .interfaces = interfaces,
        .routes = routes,
    };
}

pub fn addInterface(self: *Self, config: Interface.Config) Error!Interface.Api {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    return try self.interfaces.add(config);
}

pub fn removeInterface(self: *Self, id: Interface.Id) void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    self.interfaces.remove(id);
}

pub fn process(self: *Self) !void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    const now = self.system.clock.monotonicMicros();
    var interfaces = self.interfaces.iterator();

    while (interfaces.next()) |entry| {
        try self.processEventsIn(now, entry.interface);
    }

    interfaces = self.interfaces.iterator();

    while (interfaces.next()) |entry| {
        try self.processEventsOut(now, entry.interface, &entry.pending_out);
    }
}

fn processEventsIn(self: *Self, now: u64, interface: *Interface) !void {
    while (interface.incoming.pop()) |event_in| {
        var event = event_in;

        defer {
            event.deinit();
        }

        switch (event) {
            .announce => |announce| {
                if (self.endpoints.getPtr(announce.hash)) |endpoint| {
                    const app_data: ?[]const u8 = blk: {
                        if (announce.app_data) |app_data| {
                            break :blk app_data.items;
                        } else {
                            break :blk null;
                        }
                    };

                    const packet = try interface.packet_factory.makeAnnounce(endpoint, app_data);
                    try self.interfaces.propagate(packet, null);
                }
            },
            .packet => |*packet| {
                const header = packet.header;

                defer {
                    packet.deinit();
                }

                if (shouldDrop(packet)) {
                    return;
                }

                try packet.validate();

                if (shouldRemember(packet)) {
                    // Add packet hash to set.
                }

                packet.header.hops += 1;

                try self.processTransport(now, packet);

                try switch (header.purpose) {
                    .announce => self.processAnnounce(now, interface, packet),
                    .data => self.processData(now, packet),
                    .link_request => self.processLinkRequest(now, packet),
                    .proof => self.processProof(now, packet),
                };
            },
            .plain => |plain| {
                const packet = try interface.packet_factory.makePlain(plain.name, plain.payload);
                try self.interfaces.propagate(packet, null);
            },
        }
    }
}

fn processEventsOut(self: *Self, now: u64, interface: *Interface, pending_out: *Interface.Outgoing) !void {
    while (pending_out.pop()) |event_out| {
        var event = event_out;
        var event_sent = false;

        defer {
            if (!event_sent) {
                event.deinit();
            }
        }

        switch (event) {
            .packet => |*packet| {
                const endpoint = packet.endpoints.endpoint();
                _ = endpoint;

                const purpose = packet.header.purpose;
                const method = packet.header.method;
                const hops = packet.header.hops;

                if (purpose == .announce) {
                    try interface.outgoing.push(event);
                    event_sent = true;
                    continue;
                }

                if (method == .plain and hops == 0) {
                    try interface.outgoing.push(event);
                    event_sent = true;
                    continue;
                }

                // Put into transport if we know where it's going.
                // Otherwise broadcast.
                // Store the packet hash.
            },
        }
    }

    _ = self;
    _ = now;
}

fn processTransport(self: *Self, now: u64, packet: *Packet) !void {
    _ = now;

    if (!self.options.transport_enabled) {
        return;
    }

    if (packet.endpoints == .transport and packet.header.purpose != .announce) {
        const next_hop = packet.endpoints.nextHop();
        const our_identity = self.endpoints.main.identity orelse return Error.MissingIdentity;
        const our_hash = our_identity.hash.short();

        if (std.mem.eql(u8, &next_hop, our_hash)) {
            const endpoint = packet.endpoints.endpoint();

            if (try self.routes.hops(endpoint)) |hops| {
                if (hops == 1) {
                    packet.endpoints = .{
                        .normal = .{
                            .endpoint = endpoint,
                        },
                    };
                    packet.header.format = .normal;
                    packet.header.propagation = .broadcast;
                } else if (hops > 1) {
                    packet.endpoints.transport.transport_id = next_hop;
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

    // Link transport.
    if (packet.header.purpose != .announce and packet.header.purpose != .link_request and packet.context != .link_request_proof) {
        // If packet endpoint not in link table, return.
        // Otherwise do link table stuff and transmit.
    }
}

fn processAnnounce(self: *Self, now: u64, interface: *Interface, packet: *Packet) !void {
    try self.routes.update_from(packet, interface, now);

    if (!self.options.transport_enabled) {
        return;
    }

    // Propagating for now - will add the more sophisticated announce logic later.
    var announce = try packet.clone();
    defer {
        announce.deinit();
    }
    try announce.setTransport(self.endpoints.main.hash.short());

    try self.interfaces.propagate(announce, interface.id);
}

fn processData(self: *Self, now: u64, packet: *Packet) !void {
    _ = self;
    _ = now;
    _ = packet;
}

fn processLinkRequest(self: *Self, now: u64, packet: *Packet) !void {
    _ = self;
    _ = now;
    _ = packet;
}

fn processProof(self: *Self, now: u64, packet: *Packet) !void {
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
