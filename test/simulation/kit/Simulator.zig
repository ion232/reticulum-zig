const core = @import("core");
const std = @import("std");

const Allocator = std.mem.Allocator;
const ManualClock = @import("ManualClock.zig");
const SeededRng = @import("SeededRng.zig");

pub const Error = error{
    UnknownName,
    DuplicateName,
} || Allocator.Error;

const Interface = struct {
    api: core.Interface.Api,
    config: core.Interface.Config,
    to: []const u8,
    event_buffer: std.ArrayList(core.Node.Event.Out),
};

const Node = struct {
    node: core.Node,
    interfaces: std.StringHashMap(void),
};

// Could potentially make this a compile time function instead of a struct.
// TODO: Refactor.

const Self = @This();

ally: Allocator,
system: *core.System,
nodes: std.StringHashMap(Node),
interfaces: std.StringHashMap(Interface),

pub fn init(system: *core.System, ally: Allocator) Self {
    return Self{
        .ally = ally,
        .system = system,
        .nodes = std.StringHashMap(Node).init(ally),
        .interfaces = std.StringHashMap(Interface).init(ally),
    };
}

pub fn deinit(self: *Self) void {
    var nodes = self.nodes.valueIterator();
    var interfaces = self.interfaces.valueIterator();

    while (nodes.next()) |node| {
        node.node.deinit();
        node.interfaces.deinit();
    }

    while (interfaces.next()) |interface| {
        for (interface.event_buffer.items) |*event| {
            event.deinit();
        }

        interface.event_buffer.deinit();
    }

    self.nodes.deinit();
    self.interfaces.deinit();
    self.* = undefined;
}

pub fn fromTopology(comptime topology: anytype, system: *core.System, ally: Allocator) !Self {
    var self = Self.init(system, ally);

    inline for (std.meta.fields(@TypeOf(topology))) |node_field| {
        const node = @field(topology, node_field.name);
        // TODO: Allow for specifying some fields and defaulting others.
        var node_options: core.Node.Options = .{};
        if (@hasField(@TypeOf(node), "options")) {
            const topo_options = node.options;
            if (@hasField(@TypeOf(topo_options), "transport_enabled")) {
                node_options.transport_enabled = topo_options.transport_enabled;
            }
            if (@hasField(@TypeOf(topo_options), "incoming_packets_limit")) {
                node_options.incoming_packets_limit = topo_options.incoming_packets_limit;
            }
            if (@hasField(@TypeOf(topo_options), "outgoing_packets_limit")) {
                node_options.outgoing_packets_limit = topo_options.outgoing_packets_limit;
            }
            if (@hasField(@TypeOf(topo_options), "name")) {
                node_options.name = topo_options.name;
            }
        }
        node_options.name = node_field.name;

        const simulator_node = try self.addNode(node_field.name, node_options);

        inline for (std.meta.fields(@TypeOf(node.interfaces))) |interface_field| {
            const interface = @field(node.interfaces, interface_field.name);
            // TODO: Allow for specifying some fields and defaulting others.
            var interface_config = core.Interface.Config{};
            if (@hasField(@TypeOf(interface), "config")) {
                interface_config = interface.config;
            }

            interface_config.name = interface_field.name;

            const simulator_interface = Interface{
                .api = try simulator_node.node.addInterface(interface_config),
                .config = interface_config,
                .to = @tagName(interface.to),
                .event_buffer = std.ArrayList(core.Node.Event.Out).init(self.ally),
            };

            try simulator_node.interfaces.put(interface_field.name, {});
            try self.interfaces.put(interface_field.name, simulator_interface);
        }
    }

    return self;
}

pub fn addNode(self: *Self, name: []const u8, options: core.Node.Options) !*Node {
    if (self.nodes.contains(name)) {
        return Error.DuplicateName;
    }

    const node = Node{
        .node = try core.Node.init(self.ally, self.system, null, options),
        .interfaces = std.StringHashMap(void).init(self.ally),
    };

    try self.nodes.put(name, node);

    return self.nodes.getPtr(name).?;
}

pub fn addEndpoint(self: *Self, name: []const u8) !core.Endpoint {
    const identity = try core.Identity.random(&self.system.rng);
    var builder = core.endpoint.Builder.init(self.ally);

    _ = try builder
        .setIdentity(identity)
        .setDirection(.in)
        .setMethod(.single)
        .setApplicationName(name);

    var endpoint = try builder.build();

    if (self.indices.get(name)) |index| {
        var node = self.nodes.items[index];
        const endpoint_copy = try endpoint.clone();
        try node.endpoints.append(endpoint_copy);
    }

    return endpoint;
}

pub fn getNode(self: *Self, name: []const u8) ?*Node {
    return self.nodes.getPtr(name);
}

pub fn getInterface(self: *Self, name: []const u8) ?*Interface {
    return self.interfaces.getPtr(name);
}

pub fn stepAfter(self: *Self, count: u64, unit: ManualClock.Unit, clock: *ManualClock) !void {
    clock.advance(count, unit);
    try self.step();
}

pub fn step(self: *Self) !void {
    try self.processBuffers();
    try self.processNodes();
}

pub fn processBuffers(self: *Self) !void {
    var node_names = self.nodes.keyIterator();

    while (node_names.next()) |node_name| {
        const node = self.getNode(node_name.*).?;
        var interface_names = node.interfaces.keyIterator();

        while (interface_names.next()) |interface_name| {
            var source_interface = self.interfaces.getPtr(interface_name.*).?;
            const target_interface = self.getInterface(source_interface.to).?;

            for (source_interface.event_buffer.items) |event_out| {
                if (event_out == .packet) {
                    try target_interface.api.deliverEvent(core.Node.Event.In{
                        .packet = event_out.packet,
                    });
                }
            }

            source_interface.event_buffer.clearRetainingCapacity();
        }
    }
}

pub fn processNodes(self: *Self) !void {
    var node_names = self.nodes.keyIterator();

    while (node_names.next()) |node_name| {
        const node = self.getNode(node_name.*).?;
        try node.node.process();

        var interface_names = node.interfaces.keyIterator();
        while (interface_names.next()) |interface_name| {
            var interface = self.interfaces.getPtr(interface_name.*).?;

            while (interface.api.collectEvent()) |event_out| {
                try interface.event_buffer.append(event_out);
            }
        }
    }
}
