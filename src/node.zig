const std = @import("std");
const interface = @import("interface.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @import("endpoint.zig").Managed;
const EndpointStore = @import("endpoint/Store.zig");
const Hash = @import("crypto.zig").Hash;
const Options = @import("node/Options.zig");
const Packet = @import("packet.zig").Packet;
const RingBuffer = @import("internal/RingBuffer.zig").RingBuffer;
const System = @import("System.zig");

const Self = @This();

pub const Error = error{
    InterfaceNotFound,
    TooManyInterfaces,
    TooManyIncoming,
} || Allocator.Error;

ally: Allocator,
system: System,
options: Options,
mutex: std.Thread.Mutex,
endpoint_store: EndpointStore,
interface_engines: std.AutoHashMap(interface.Id, *interface.Engine),
incoming: std.RingBuffer(Element.In),
routes: std.StringHashMap(Hash),
current_interface_id: interface.Id,

pub fn init(ally: Allocator, system: System, options: Options) Allocator.Error!Self {
    return .{
        .ally = ally,
        .system = system,
        .options = options,
        .mutex = .{},
        .endpoint_store = .{},
        .interface_engines = std.AutoHashMap(interface.Id, *interface.Engine).init(ally),
        .incoming = try std.RingBuffer(Element.In).init(ally, options.max_incoming_packets),
        .routes = std.StringHashMap(Hash).init(ally),
        .current_interface_id = 0,
    };
}

pub fn deinit(self: *Self) void {
    self.interfaces.deinit();
    self.incoming.deinit(self.ally);
    self.outgoing.deinit();
    self.* = undefined;
}

pub fn addInterface(self: *Self, config: interface.Config) Error!*interface.Engine {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    if (self.interface_engines.count() > self.options.max_interfaces) {
        return Error.TooManyInterfaces;
    }

    const engine = try self.ally.create(interface.Engine);
    engine.* = interface.Engine.init(self.ally, config);

    try self.interface_engines.put(self.current_interface_id, engine);
    self.current_interface_id += 1;

    return engine;
}

pub fn removeInterface(self: *Self, id: interface.Id) Error!void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    if (self.interface_engines.get(id)) |engine| {
        engine.clear();
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

    const front = self.receiver.queue.peek();
    if (front == null) {
        return;
    }

    const now = self.system.clock.monotonicTime();
    const element = front.?;
    const packet = &element.packet;
    const header = &packet.header;

    defer {
        self.ally.free(element.raw_data);
    }

    if (self.shouldDrop(packet)) {
        return;
    }

    _ = now;
    header.hops += 1;

    if (header.purpose == .announce) {
        const destination_hash = switch (packet.endpoints) {
            .normal => |*n| ,
            .transport => |*t| ,
        };
    }
}

pub fn receive(self: *Self, id: interface.Id, packet: Packet) !void {
    // Could replace this by using a thread safe queue.
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    try self.incoming.push(.{
        .packet = packet,
        .id = id,
    });
}

pub fn send(self: *Self, id: interface.Id, packet: Packet) !void {
    self.mutex.lock();

    defer {
        self.mutex.unlock();
    }

    // TODO: Processing code.

    if (self.interface_engines.get(id)) |engine| {
        engine.send(.{ .single = id }, packet);
    }
}

fn shouldDrop(self: *Self, packet: *Packet) bool {
    _ = self;
    _ = packet;
    return false;
}

const Element = struct {
    const In = struct {
        id: interface.Id,
        packet: Packet,
    };
    const Out = struct {
        data: []const u8,
    };
};
