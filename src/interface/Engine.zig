const std = @import("std");
const interface = @import("../interface.zig");
const Id = interface.Id;
const Config = interface.Config;
const Packet = @import("../packet.zig").Packet;
const RingBuffer = @import("../internal/RingBuffer.zig").RingBuffer;

pub const Target = union(enum) {
    single: interface.Id,
    all: void,
};

const Self = @This();

queues: std.AutoHashMap(Id, u8),
interfaces: std.AutoHashMap(Id, Config),

pub fn init() Self {}

pub fn addInterface(self: *Self, interface: Interface) Error!interface.Id {
    if (self.interfaces.items.len == self.interfaces.capacity) {
        return Error.TooManyInterfaces;
    }

    const queue = Queue(.out).init(
        self.ally,
        self.config.max_outgoing_packets,
    );

    for (0.., self.interfaces.items) |id, *entry| {
        if (entry.* == null) {
            entry.* = interface;
            self.outgoing.items[id] = queue;
            return id;
        }
    }

    const id = self.interfaces.items.len;
    try self.interfaces.append(interface);
    try self.outgoing.append(queue);

    return id;
}

pub fn removeInterface(self: *Self, id: interface.Id) Error!void {
    if (id >= self.interfaces.items.len or id >= self.outgoing.items.len) {
        return Error.InvalidInterfaceId;
    }
    self.interfaces[id] = null;
    self.outgoing[id].deinit();
    self.outgoing[id] = null;
}

pub fn receive(id: Id) void {
    //
}

pub fn send(target: Target) void {
    //
}

const Queue = RingBuffer(Packet);

// ptr: *anyopaque,
// sendFn: *const fn (ptr: *anyopaque) u64,

// fn send(self: *Self) u64 {
//     return self.sendFn(self.ptr);
// }
