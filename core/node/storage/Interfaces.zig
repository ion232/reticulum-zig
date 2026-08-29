const builtin = @import("builtin");
const std = @import("std");
const unit = @import("../unit.zig");

const Allocator = std.mem.Allocator;
const Direction = @import("../endpoint.zig").Direction;
const Event = @import("../node/Event.zig");
const Egress = @import("Egress.zig");
const Ingress = @import("Ingress.zig");
const Interface = @import("../Interface.zig");
const Packet = @import("../packet/Managed.zig");
const PacketFactory = @import("../packet/Factory.zig");
const System = @import("../System.zig");

const Self = @This();

pub const Error = error{
    InterfaceNotFound,
    TooManyInterfaces,
} || Allocator.Error;

const Entry = struct {
    const Metrics = struct {
        last_seen: u64,
        bytes_in: u64,
        bytes_out: u64,
    };

    interface: *Interface,
    metrics: Metrics,
    egress: Egress,
    ingress: Ingress,
    creation_time: u64,
};

const interface_limit = if (builtin.os.tag == .freestanding) 48 else 1024;

ally: Allocator,
system: System,
entries: std.AutoHashMap(Interface.Id, Entry),
current_interface_id: Interface.Id,

pub fn init(ally: Allocator, system: System) Self {
    return Self{
        .ally = ally,
        .system = system,
        .entries = std.AutoHashMap(Interface.Id, Entry).init(ally),
        .current_interface_id = 0,
    };
}

pub fn iterator(self: *Self) std.AutoHashMap(Interface.Id, Entry).ValueIterator {
    return self.entries.valueIterator();
}

pub fn getPtr(self: *Self, id: Interface.Id) ?*Interface {
    if (self.entries.getPtr(id)) |entry| {
        return entry.interface;
    }

    return null;
}

pub fn process(self: *Self, now: u64) !void {
    var entries = self.entries.valueIterator();

    while (entries.next()) |entry| {
        ingress.process(entry);
    }
}

pub fn updateMetrics(
    self: *Self,
    id: Interface.Id,
    direction: Direction,
    packet: *const Packet,
    now: u64,
) void {
    if (self.entries.getPtr(id)) |entry| {
        const bytes = packet.size();

        switch (direction) {
            .in => entry.bytes_in += bytes,
            .out => entry.bytes_out += bytes,
        }

        entry.last_seen = now;
    }
}

pub fn add(self: *Self, config: Interface.Config, now: u64) Error!Interface.Api {
    if (self.entries.count() >= interface_limit) return Error.TooManyInterfaces;

    const id = self.current_interface_id;
    self.current_interface_id += 1;

    const incoming = try self.ally.create(Interface.Incoming);
    incoming.* = Interface.Incoming.init(self.ally);

    errdefer self.ally.destroy(incoming);

    const outgoing = try self.ally.create(Interface.Outgoing);
    outgoing.* = Interface.Outgoing.init(self.ally);

    errdefer self.ally.destroy(outgoing);

    const packet_factory = PacketFactory.init(
        self.ally,
        self.system.rng,
        config,
    );

    const interface = try self.ally.create(Interface);

    errdefer self.ally.destroy(interface);

    interface.* = Interface.init(
        self.ally,
        config,
        id,
        incoming,
        outgoing,
        packet_factory,
    );

    try self.entries.put(id, Entry{
        .interface = interface,
        .pending = .init(self.ally),
        .metrics = .{
            .bytes_in = 0,
            .bytes_out = 0,
            .last_seen = now,
        },
        .egress_control = .{
            .announce_capacity = 2,
            .announce_release_time = now,
            .announce_queue = .init(self.ally, {}),
        },
        .ingress_control = .{
            .burst_activated = 0,
            .burst_active = false,
            .burst_freq = 12 * 1_000_000,
            .burst_freq_new = 4 * 1_000_000,
            .burst_hold = 60 * 1_000_000,
            .burst_penalty = 5 * 60 * 1_000_000,
            .held_release = 0,
            .new_time = 2 * 60 * 60 * 1_000_000,
            .incoming_announce_times = Entry.IngressControl.IncomingAnnounceTimes.init(),
        },
        .held_announces = .init(self.ally),
        .creation_time = now,
    });

    return interface.api();
}

pub fn remove(self: *Self, id: Interface.Id) void {
    if (self.entries.get(id)) |entry| {
        entry.interface.deinit(self.ally);
        self.ally.destroy(entry.interface);
        self.entries.remove(id);
        self.current_interface_id -= 1;
    }
}

pub fn unicast(self: *Self, packet: *const Packet, id: Interface.Id) !void {
    const entry = self.entries.getPtr(id) orelse return Error.InterfaceNotFound;
    try entry.pending.writeItem(.{
        .event = .{
            .packet = try packet.clone(),
        },
    });
}

pub fn broadcast(self: *Self, packet: Packet) !void {
    var entries = self.entries.valueIterator();

    while (entries.next()) |entry| {
        if (packet.interface_id) |id| {
            if (entry.interface.id == id) continue;
        }
        try entry.pending.writeItem(.{
            .event = .{
                .packet = try packet.clone(),
            },
        });
    }
}

pub fn deinit(self: *Self) void {
    var entries = self.entries.valueIterator();

    while (entries.next()) |entry| {
        while (entry.pending.readItem()) |e| {
            var event = e.event;
            event.deinit();
        }

        var held_announces = entry.held_announces.iterator();

        while (held_announces.next()) |announce| {
            self.ally.free(announce.key_ptr.*);
            announce.value_ptr.deinit();
        }

        entry.held_announces.deinit();
        entry.pending.deinit();
        entry.interface.deinit();
        self.ally.destroy(entry.interface);
    }

    self.entries.deinit();
    self.* = undefined;
}
