const builtin = @import("builtin");
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
const PacketFilter = @import("packet.zig").Filter;
const Ratchets = @import("Ratchets.zig");
const Routes = @import("Routes.zig");
const Name = @import("endpoint/Name.zig");
const ThreadSafeFifo = @import("internal/ThreadSafeFifo.zig").ThreadSafeFifo;
const System = @import("System.zig");

pub const Error = error{} || Interfaces.Error || Packet.ValidationError || Identity.Error || EndpointBuilder.Error || Name.Error || Allocator.Error;

const Self = @This();

ally: Allocator,
mutex: std.Thread.Mutex,
system: System,
options: Options,
endpoints: Endpoints,
interfaces: Interfaces,
ratchets: Ratchets,
routes: Routes,
packet_filter: PacketFilter,

pub fn init(ally: Allocator, system: *System, identity: ?Identity, options: Options) Error!Self {
    var endpoint_builder = EndpointBuilder.init(ally);
    var main_endpoint = try endpoint_builder
        .setIdentity(identity orelse try Identity.random(&system.rng))
        .setDirection(.in)
        .setVariant(.single)
        .setName(try Name.init(options.name, &.{}, ally))
        .build();
    defer main_endpoint.deinit();
    const endpoints = try Endpoints.init(ally, &main_endpoint);
    const interfaces = Interfaces.init(ally, system.*);
    const ratchets = Ratchets.init(ally, &system.rng);
    const routes = Routes.init(ally);
    const packet_filter_capacity = if (builtin.target.os.tag == .freestanding and builtin.cpu.arch != .wasm32) 2048 else 32768;
    const packet_filter = try PacketFilter.init(ally, packet_filter_capacity);

    return .{
        .ally = ally,
        .mutex = .{},
        .system = system.*,
        .options = options,
        .endpoints = endpoints,
        .interfaces = interfaces,
        .ratchets = ratchets,
        .routes = routes,
        .packet_filter = packet_filter,
    };
}

pub fn addInterface(self: *Self, config: Interface.Config) Error!Interface.Api {
    self.mutex.lock();
    defer self.mutex.unlock();

    return try self.interfaces.add(config);
}

pub fn removeInterface(self: *Self, id: Interface.Id) void {
    self.mutex.lock();
    defer self.mutex.unlock();

    self.interfaces.remove(id);
}

pub fn mainEndpoint(self: *Self) Hash {
    self.mutex.lock();
    defer self.mutex.unlock();

    return self.endpoints.main.hash;
}

pub fn process(self: *Self) !void {
    self.mutex.lock();
    defer self.mutex.unlock();

    const now = self.system.clock.monotonicMicros();
    var interfaces = self.interfaces.iterator();

    while (interfaces.next()) |entry| {
        try self.eventsIn(entry.interface, now);
    }

    interfaces = self.interfaces.iterator();

    while (interfaces.next()) |entry| {
        try self.eventsOut(entry.interface, &entry.pending_out);
    }
}

fn eventsIn(self: *Self, interface: *Interface, now: u64) !void {
    while (interface.incoming.pop()) |event_in| {
        var event = event_in;
        defer event.deinit();

        try switch (event) {
            .announce => |*announce| self.announceTask(interface, announce, now),
            .packet => |*packet| self.packetIn(interface, packet, now),
            .plain => |*plain| self.plainTask(interface, plain),
        };
    }
}

fn eventsOut(self: *Self, interface: *Interface, pending_out: *Interface.Outgoing) !void {
    while (pending_out.pop()) |event_out| {
        var event = event_out;

        const not_sent = switch (event) {
            .packet => |*packet| self.packetOut(interface, packet),
        } catch true;

        if (not_sent) {
            event.deinit();
        }
    }
}

fn announceTask(self: *Self, interface: *Interface, announce: *Event.In.Announce, now: u64) !void {
    const endpoint = self.endpoints.get(announce.hash.short()) orelse return;
    const app_data: ?[]const u8 = blk: {
        if (announce.app_data) |app_data| {
            break :blk app_data.items;
        } else {
            break :blk null;
        }
    };

    var packet = try interface.packet_factory.makeAnnounce(endpoint, app_data, now);
    defer packet.deinit();

    try self.interfaces.broadcast(packet, null);
}

fn packetIn(self: *Self, interface: *Interface, packet: *Packet, now: u64) !void {
    const header = packet.header;

    if (self.shouldDrop(packet)) {
        return;
    }

    try packet.validate();

    // TODO: Don't add the endpoint if it's in the link table.
    if (header.purpose != .proof or packet.context != .link_request_proof) {
        self.packet_filter.add(packet);
    }

    packet.header.hops += 1;

    try self.transport(now, packet);

    try switch (header.purpose) {
        .announce => self.announcePacketIn(now, interface, packet),
        .data => self.dataPacketIn(now, packet),
        .link_request => self.linkRequestPacketIn(now, packet),
        .proof => self.proofPacketIn(now, packet),
    };
}

fn plainTask(self: *Self, interface: *Interface, plain: *Event.In.Plain) !void {
    const packet = try interface.packet_factory.makePlain(plain.name, plain.payload);
    try self.interfaces.broadcast(packet, null);
}

fn packetOut(self: *Self, originating_interface: ?*Interface, packet: *Packet, now: u64) !bool {
    _ = self;

    const purpose = packet.header.purpose;
    const variant = packet.header.endpoint;
    const hops = packet.header.hops;

    var transmitted = false;

    // TODO: Handle tracking packet delivery here.

    const endpoint = packet.endpoints.endpoint();

    if (self.routes.get(endpoint)) |route| {
        if (purpose != .announce and variant != .plain and variant != .group) {
            if (route.hops > 1 and packet.header.format == .normal) {
                packet.header.format = .transport;
                packet.endpoints = .{
                    .transport = .{
                        .endpoint = endpoint,
                        .transport_id = route.next_hop,
                    },
                };
            }

            self.routes.setLastSeen(endpoint, now);
            try interface.outgoing.push(.{ .packet = packet.* });
            transmitted = true;
        }
    } else {
        var should_transmit = true;

        // TODO: If the endpoint variant is a link, don't transmit if closed.
        // TODO: If interface is not the one we expect for this packet, don't transmit.
        
        if (purpose == .announce and originating_interface == null) {
            switch (interface.mode) {
                .access_point => should_transmit = false,
                .roaming => if (self.endpoints.get(endpoint)) |_| {
                    // TODO: If has associated interface and that interface is in roaming or boundary, do not transmit.
                },
                .boundary => if (self.endpoints.get(endpoint)) |_| {
                    // TODO: If has associated interface and that interface is in roaming, do not transmit.
                },
                else => if (hops > 0) {
                    // Get announce cap, announce_allowed_at and announce_queue.
                    // If interface queue has announces and now is past announce_allowed_at:
                    // Get wait time from bit rate and packet size.
                    // Set interface announce allowed at, whatever that means.

                    // Else:
                    should_transmit = false;
                    // If not max announce queue length:
                    var should_queue = false;
                    // If there's already a similar announce in the queue and the current announce is newer, replace it with that one.
                    // Make sure the priority queue is recalculated to reflect this.
                    // should_queue = false if we replace an entry.
                    // Otherwise, make an entry, using the timestamp from the packet noise, and add it.
                    // If the interface queue was empty, send a process task out so that the announce queue gets processed.
                },
            }
        }

        if (should_transmit) {
            // Add the packet hash to the filter, but make sure to only do it once.
            // Transmit the packet.
        }
    }

    return true;
}

fn transport(self: *Self, now: u64, packet: *Packet) !void {
    if (!self.options.transport_enabled) {
        return;
    }

    // General transport.
    if (packet.endpoints == .transport and packet.header.purpose != .announce) {
        blk: {
            const next_hop = packet.endpoints.nextHop();
            const our_identity = self.endpoints.main.identity orelse return Error.MissingIdentity;
            const our_hash = our_identity.hash.short();

            if (!std.mem.eql(u8, &next_hop, our_hash)) {
                break :blk;
            }

            const endpoint = packet.endpoints.endpoint();
            const route = self.routes.get(endpoint) orelse break :blk;

            if (route.hops == 1) {
                packet.endpoints = .{ .normal = .{ .endpoint = endpoint } };
                packet.header.format = .normal;
                packet.header.propagation = .broadcast;
            } else if (route.hops > 1) {
                packet.endpoints.transport.transport_id = route.next_hop;
            }

            if (packet.header.purpose == .link_request) {
                // Link request stuff.
            } else {
                // Add to reverse table [hash.packet] = [if_in, if_out, timestamp] for link transport.
            }

            self.routes.setLastSeen(endpoint, now);
            try self.interfaces.transmit(packet, route.source_interface);
        }
    }

    // Link transport.
    if (packet.header.purpose != .announce and packet.header.purpose != .link_request and packet.context != .link_request_proof) {
        // If packet endpoint not in link table, return.
        // Otherwise do link table stuff and transmit.
    }
}

fn announcePacketIn(self: *Self, now: u64, interface: *Interface, packet: *Packet) !void {
    if (packet.payload != .announce) {
        return Error.InvalidAnnounce;
    }

    const max_hops = 128;
    const endpoint = packet.endpoints.endpoint();
    const hops = packet.header.hops;
    const noise = packet.payload.announce.noise;
    const timestamp = packet.payload.announce.timestamp;

    // If hash isn't in routes, apply potential ingress limiting, hold packet and return.
    // If not one of our endpoints and packet is in transport:
    // Get announce entry from table.
    // If entry hops is hops - 1, increment local broadcast count and if at max then remove from table.
    // If entry hops is hops - 2 and retries is more than 0 and retransmission timeout reached, remove from table.

    if (self.endpoints.has(&endpoint) or hops >= max_hops) {
        return;
    }

    if (self.routes.get(endpoint)) |route| {
        if (route.has(timestamp, noise)) {
            if (timestamp != route.latest_timestamp or route.state != .unresponsive) {
                return;
            }
        }

        const better_route = (hops <= route.hops and timestamp > route.latest_timestamp);
        const route_expired = now >= route.expiry_time;
        const newer_route = timestamp >= route.latest_timestamp;

        if (!(better_route or route_expired or newer_route)) {
            return;
        }
    }

    self.routes.setState(endpoint, .unknown);


    if (self.options.transport_enabled and packet.context != .path_response) {
        // Needs announce rate implementation.
        const rate_blocked = false;

        if (rate_blocked) {
            std.log.debug("Propagation of announce ({s}) was rate blocked.", .{endpoint});
        } else {
            // Should be put in to announce table.
            var announce = try packet.clone();
            defer announce.deinit();

            try announce.setTransport(self.endpoints.main.hash.short());
            try self.interfaces.broadcast(announce, interface.id);
        }
    }

    // Check if the announce matches any discovery path requests and answer it if so.
    // (implementation needed).

    try self.routes.updateFrom(packet, interface, now);
}

fn dataPacketIn(self: *Self, now: u64, packet: *Packet) !void {
    _ = self;
    _ = now;
    _ = packet;
}

fn linkRequestPacketIn(self: *Self, now: u64, packet: *Packet) !void {
    _ = self;
    _ = now;
    _ = packet;
}

fn proofPacketIn(self: *Self, now: u64, packet: *Packet) !void {
    _ = self;
    _ = now;
    _ = packet;
}

fn shouldDrop(self: *Self, packet: *const Packet) !void {
    const endpoint = packet.header.endpoint;
    const purpose = packet.header.purpose;
    const hops = packet.header.hops;

    if (packet.endpoints == .transport and purpose != .announce) {
        if (!std.mem.eql(u8, packet.endpoints.nextHop()[0..], self.endpoints.main.hash.short()[0..])) {
            return true;
        }
    }

    switch (packet.context) {
        .keep_alive, .resource_request, .resource_proof, .resource, .cache_request, .link_channel => return false;
        else => switch (endpoint) {
            .plain, .group => return purpose == .announce or hops > 1,
            else => return !(self.packet_filter.has(packet) and purpose == .announce and endpoint == .single);
        }
    }
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
    self.packet_filter.deinit();
}
