const std = @import("std");

const Allocator = std.mem.Allocator;
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
    interface: *Interface,
    pending_out: Interface.Outgoing,
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

pub fn add(self: *Self, config: Interface.Config) Error!Interface.Api {
    if (self.entries.count() >= interface_limit) {
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

    try self.entries.put(id, Entry{
        .interface = interface,
        .pending_out = Interface.Outgoing.init(self.ally),
    });

    return interface.api();
}

pub fn remove(self: *Self, id: Interface.Id) void {
    if (self.entries.get(id)) |entry| {
        entry.interface.deinit(self.ally);
        self.ally.destroy(entry.interface);
        self.entries.remove(id);
    }
}

// TODO: Refactor source_id.
pub fn propagate(self: *Self, packet: Packet, source_id: ?Interface.Id) !void {
    var entries = self.entries.valueIterator();

    while (entries.next()) |entry| {
        if (source_id) |source| {
            if (entry.interface.id == source) {
                continue;
            }
        }

        try entry.pending_out.push(.{
            .packet = try packet.clone(),
        });
    }
}

pub fn deinit(self: *Self) void {
    var entries = self.entries.valueIterator();

    while (entries.next()) |entry| {
        while (entry.pending_out.pop()) |event| {
            var e = event;
            e.deinit();
        }
        entry.pending_out.deinit();
        entry.interface.deinit();
        self.ally.destroy(entry.interface);
    }

    self.entries.deinit();
    self.* = undefined;
}
