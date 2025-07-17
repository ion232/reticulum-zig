const builtin = @import("builtin");
const std = @import("std");
const unit = @import("../unit.zig");

const Allocator = std.mem.Allocator;
const Direction = @import("../endpoint.zig").Direction;
const Event = @import("../node/Event.zig");
const Interface = @import("../Interface.zig");
const Packet = @import("../packet/Managed.zig");
const PacketFactory = @import("../packet/Factory.zig");
const System = @import("../System.zig");

const Self = @This();

pub const Error = error{
    InterfaceNotFound,
    TooManyInterfaces,
} || Allocator.Error;

pub const Pending = std.fifo.LinearFifo(Entry.PendingEvent, .Dynamic);
pub const AnnounceEntry = struct {
    announce: Packet,
    timestamp: u64,
};

pub const EgressControl = struct {
    pub const max_queued_announces = if (builtin.target.os.tag == .freestanding) 32 else 16384;

    const AnnounceQueue = std.PriorityQueue(AnnounceEntry, compareAnnounces);

    announce_queue: AnnounceQueue,
    announce_release_time: u64,
    announce_capacity: u8,
};

const Entry = struct {
    const PendingEvent = struct {
        event: Event.Out,
        origin_id: Interface.Id,
    };

    const Metrics = struct {
        last_seen: u64,
        bytes_in: u64,
        bytes_out: u64,
    };

    const IngressControl = struct {
        held_release: u64,
        new_time: u64,
        burst_active: bool,
        burst_freq: u64,
        burst_freq_new: u64,
        burst_hold: u64,
        burst_activated: u64,
        burst_penalty: u64,
        incoming_announce_times: std.fifo.LinearFifo(u64, .{ .Static = 6 }),

        fn announceFrequencyIn(self: @This(), now: u64) u64 {
            const count = self.incoming_announce_times.count;

            if (count < 1) return 0;

            var sum = now - self.incoming_announce_times.peekItem(count - 1);

            for (1..count) |i| {
                sum += self.incoming_announce_times.peekItem(i) - self.incoming_announce_times.peekItem(i - 1);
            }

            const average = if (sum != 0) (1_000_000 * count) / sum else 0;

            return average;
        }
    };

    interface: *Interface,
    pending: Pending,
    metrics: Metrics,
    egress_control: EgressControl,
    ingress_control: IngressControl,
    held_announces: std.StringArrayHashMap(Packet),
    creation_time: u64,
};

const interface_limit = 256;

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

pub fn shouldIngressLimit(self: *Self, id: Interface.Id, now: u64) !bool {
    const entry = self.entries.getPtr(id) orelse return Error.InterfaceNotFound;
    const lifetime = now - entry.creation_time;
    const control = &entry.ingress_control;

    const frequency = entry.ingress_control.announceFrequencyIn(now);
    const threshold = if (lifetime < control.new_time) control.burst_freq_new else control.burst_freq;

    if (control.burst_active) {
        if (frequency < threshold and now > control.burst_activated + control.burst_hold) {
            control.burst_active = false;
            control.held_release = now + control.burst_penalty;
        }

        return true;
    } else {
        if (frequency > threshold) {
            control.burst_active = true;
            control.burst_activated = now;
            return true;
        }

        return false;
    }
}

pub fn holdAnnounce(self: *Self, id: Interface.Id, announce: Packet) !void {
    const entry = self.entries.getPtr(id) orelse return Error.InterfaceNotFound;

    const max_held_announces = 256;
    if (entry.held_announces.count() > max_held_announces) return;

    const endpoint = announce.endpoints.endpoint();
    const key = try self.ally.dupe(u8, &endpoint);
    try entry.held_announces.put(key, announce);
}

pub fn updateMetrics(
    self: *Self,
    id: Interface.Id,
    direction: Direction,
    packet: *const Packet,
    now: u64,
) void {
    if (self.entries.getPtr(id)) |entry| {
        switch (direction) {
            .in => entry.bytes_in += packet.size(),
            .out => entry.bytes_out += packet.size(),
        }

        entry.last_seen = now;
    }
}

pub fn add(self: *Self, config: Interface.Config) Error!Interface.Api {
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
        .pending = Entry.Pending.init(self.ally),
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

pub fn transmit(self: *Self, packet: *const Packet, id: Interface.Id, origin_id: ?Interface.Id) !void {
    const entry = self.entries.getPtr(id) orelse return Error.InterfaceNotFound;
    try entry.pending.writeItem(.{
        .event = .{
            .packet = try packet.clone(),
        },
        .origin_id = origin_id,
    });
}

pub fn broadcast(self: *Self, packet: Packet, origin_id: ?Interface.Id) !void {
    var entries = self.entries.valueIterator();

    while (entries.next()) |entry| {
        if (origin_id) |id| {
            if (entry.interface.id == id) continue;
        }

        try entry.pending.writeItem(.{
            .event = .{
                .packet = try packet.clone(),
            },
            .origin_id = origin_id,
        });
    }
}

pub fn deinit(self: *Self) void {
    var entries = self.entries.valueIterator();

    while (entries.next()) |entry| {
        while (entry.pending.pop()) |event| {
            var e = event;
            e.deinit();
        }

        var held_announces = entry.held_announces.iterator();

        while (held_announces.next()) |announce| {
            self.ally.free(announce.key_ptr);
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

fn compareAnnounces(ctx: void, a: Packet, b: Packet) std.math.Order {
    _ = ctx;

    return std.math.order(a.header.hops, b.header.hops);
}
