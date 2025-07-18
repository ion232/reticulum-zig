const builtin = @import("builtin");
const std = @import("std");

pub const Event = @import("node/Event.zig");
pub const Options = @import("node/Options.zig");

const Allocator = std.mem.Allocator;
const Announces = @import("Announces.zig");
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
announces: Announces,
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
    const announces = Announces.init(ally);
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
        .announces = announces,
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

    // Active and pending links.
    // Timed out packets.
    // Invalidated path requests.
    // Path request timeouts.
    // Reverse table timeouts.
    // Link timeouts.
    // Route timeouts.
    // Packet cache.

    const outgoing = std.ArrayList(Packet).init(self.ally);

    try self.announces.process(outgoing, now);
    try self.interfaces.process(now);

    for (outgoing) |entry| {
        const interface = self.interfaces.getPtr(entry.interface_id) orelse continue;
        interface.outgoing.push(entry.packet);
    }

    var interfaces = self.interfaces.iterator();

    while (interfaces.next()) |entry| {
        try self.eventsIn(entry.interface, now);
    }

    interfaces = self.interfaces.iterator();

    while (interfaces.next()) |entry| {
        try self.eventsOut(entry.interface, &entry.pending, &entry.egress_control, now);
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

fn eventsOut(self: *Self, interface: *Interface, pending: *Interfaces.Pending, egress_control: *Interfaces.EgressControl, now: u64) !void {
    while (pending.pop()) |entry| {
        var event = entry.event;
        const origin_interface = if (entry.origin_id) |id| self.interfaces.getPtr(id) else null;

        const not_sent = switch (event) {
            .packet => |*packet| self.packetOut(
                interface,
                origin_interface,
                egress_control,
                packet,
                now,
            ),
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
        .announce => self.announcePacketIn(interface, packet, now),
        .data => self.dataPacketIn(packet, now),
        .link_request => self.linkRequestPacketIn(packet, now),
        .proof => self.proofPacketIn(packet, now),
    };
}

fn plainTask(self: *Self, interface: *Interface, plain: *Event.In.Plain) !void {
    const packet = try interface.packet_factory.makePlain(plain.name, plain.payload);
    try self.interfaces.broadcast(packet, null);
}

fn packetOut(self: *Self, interface: *Interface, origin_interface: ?*Interface, egress_control: *Interfaces.EgressControl, packet: *Packet, now: u64) !bool {
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

        if (purpose == .announce and origin_interface == null) {
            should_transmit = blk: {
                const route = self.routes.get(&endpoint) orelse break :blk false;
                const next_hop_interface = self.interfaces.getPtr(route.origin_interface_id) orelse break :blk false;

                switch (interface.mode) {
                    .access_point => break :blk false,
                    .roaming => if (!self.endpoints.has(endpoint)) {
                        break :blk switch (next_hop_interface.mode) {
                            .roaming, .boundary => false,
                            else => true,
                        };
                    },
                    .boundary => if (!self.endpoints.has(endpoint)) {
                        break :blk switch (next_hop_interface.mode) {
                            .roaming => false,
                            else => true,
                        };
                    },
                    else => if (hops > 0) {
                        if (egress_control.announce_queue.count() == 0 and now >= egress_control.announce_release_time and interface.bit_rate != null) {
                            const bit_rate = interface.bit_rate orelse unreachable;
                            const transmission_time = packet.size() / bit_rate;
                            egress_control.announce_release_time = now + (transmission_time / egress_control.announce_capacity);
                        } else {
                            should_transmit = false;

                            if (egress_control.announce_queue.count() >= Interfaces.EgressControl.max_queued_announces) {
                                var announce_entries = egress_control.announce_queue.iterator();
                                var matching_entry: ?*Interfaces.AnnounceEntry = null;

                                while (announce_entries.next()) |*entry| {
                                    if (std.mem.eql(u8, entry.announce.packet.endpoints.endpoint(), packet.endpoints.endpoint())) {
                                        matching_entry = entry;
                                        break;
                                    }
                                }

                                if (matching_entry) |entry| {
                                    if (packet.payload.announce.timestamp > entry.announce.payload.announce.timestamp) {
                                        entry.* = .{
                                            .announce = try packet.clone(),
                                            .timestamp = now,
                                        };
                                    }
                                } else {
                                    try egress_control.announce_queue.add(.{
                                        .timestamp = now,
                                        .packet = try packet.clone(),
                                    });

                                    if (egress_control.announce_queue.count() == 0 and egress_control.announce_release_time > now) {
                                        try interface.outgoing.push(.{
                                            .task = .{
                                                .process = .{
                                                    .at = egress_control.announce_release_time,
                                                },
                                            },
                                        });
                                    }
                                }
                            }
                        }
                    },
                }

                break :blk true;
            };
        }

        if (should_transmit) {
            self.packet_filter.add(packet);
            interface.outgoing.push(packet);
            transmitted = true;
        }
    }

    return transmitted;
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
            try self.interfaces.transmit(packet, route.origin_interface_id);
        }
    }

    // Link transport.
    if (packet.header.purpose != .announce and packet.header.purpose != .link_request and packet.context != .link_request_proof) {
        // If packet endpoint not in link table, return.
        // Otherwise do link table stuff and transmit.
    }
}

fn announcePacketIn(self: *Self, interface: *Interface, announce: *Packet, now: u64) !void {
    if (announce.payload != .announce) return Error.InvalidAnnounce;

    const max_hops = 128;
    const endpoint = announce.endpoints.endpoint();
    const hops = announce.header.hops;
    const noise = announce.payload.announce.noise;
    const timestamp = announce.payload.announce.timestamp;

    if (!self.routes.has(&endpoint) and self.interfaces.shouldIngressLimit(interface.id, now)) {
        self.interfaces.holdAnnounce(interface.id, try announce.clone());
        return;
    }

    if (self.endpoints.has(&endpoint) or hops >= max_hops) return;

    if (self.options.transport_enabled and announce.endpoints == .transport) {
        if (self.announces.getPtr(&endpoint)) |entry| {
            if (entry.hops == hops - 1) {
                entry.rebroadcasts += 1;
                if (entry.rebroadcasts >= 2) self.announces.remove(&endpoint);
            } else if (entry.hops == hops - 2 and entry.retries > 0) {
                if (now < entry.retransmit_timeout) self.announces.remove(&endpoint);
            }
        }
    }

    if (self.routes.get(endpoint)) |route| {
        if (route.has(timestamp, noise)) {
            if (timestamp != route.latest_timestamp or route.state != .unresponsive) return;
        }

        const better_route = (hops <= route.hops and timestamp > route.latest_timestamp);
        const route_expired = now >= route.expiry_time;
        const newer_route = timestamp >= route.latest_timestamp;

        if (!(better_route or route_expired or newer_route)) return;
    }

    self.routes.setState(endpoint, .unknown);

    if (self.options.transport_enabled and announce.context != .path_response) {
        const retransmit_delay = self.system.rng.intRangeAtMost(u64, 0, 500_000);
        try self.announces.add(
            endpoint,
            try announce.clone(),
            interface.id,
            hops,
            retransmit_delay,
            now,
        );
    }

    // TODO: Check if the announce matches any discovery path requests and answer it if so.
    // TODO: Cache packet if announce.

    try self.routes.updateFrom(announce, interface, now);
}

fn dataPacketIn(self: *Self, packet: *Packet, now: u64) !void {
    _ = self;
    _ = now;
    _ = packet;
}

fn linkRequestPacketIn(self: *Self, packet: *Packet, now: u64) !void {
    _ = self;
    _ = now;
    _ = packet;
}

fn proofPacketIn(self: *Self, packet: *Packet, now: u64) !void {
    _ = self;
    _ = now;
    _ = packet;
}

fn shouldDrop(self: *Self, packet: *const Packet) !bool {
    const endpoint = packet.header.endpoint;
    const purpose = packet.header.purpose;
    const hops = packet.header.hops;

    if (packet.endpoints == .transport and purpose != .announce) {
        if (!std.mem.eql(u8, packet.endpoints.nextHop()[0..], self.endpoints.main.hash.short()[0..])) {
            return true;
        }
    }

    switch (packet.context) {
        .keep_alive, .resource_request, .resource_proof, .resource, .cache_request, .link_channel => return false,
        else => switch (endpoint) {
            .plain, .group => return purpose == .announce or hops > 1,
            else => return !(self.packet_filter.has(packet) and purpose == .announce and endpoint == .single),
        },
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
    self.ratchets.deinit();
    self.routes.deinit();
    self.announces.deinit();
    self.packet_filter.deinit();
}
