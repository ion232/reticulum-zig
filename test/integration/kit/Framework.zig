const std = @import("std");
const rt = @import("reticulum");

const Allocator = std.mem.Allocator;
const Clock = @import("Clock.zig");

pub const Error = error{
    UnknownName,
    DuplicateName,
} || Allocator.Error;

const Interface = struct {
    api: rt.Interface.Api,
    config: rt.Interface.Config,
    to: std.StringHashMap(void),
};

const Node = struct {
    node: rt.Node,
    interfaces: std.StringHashMap(Interface),
};

// Could potentially make this a compile time function instead of a struct.

const Self = @This();

ally: Allocator,
clock: Clock,
system: rt.System,
nodes: std.StringHashMap(Node),
interfaces: std.StringHashMap(Interface),

pub fn init(ally: Allocator) Self {
    var clock = Clock.init();

    return Self{
        .ally = ally,
        .clock = clock,
        .system = rt.System{
            .clock = clock.clock(),
            .rng = std.crypto.random,
        },
        .nodes = std.StringHashMap(Node).init(ally),
        .interfaces = std.StringHashMap(Interface).init(ally),
    };
}

pub fn fromTopology(comptime topology: anytype, ally: Allocator) !Self {
    var clock = Clock.init();

    var self = Self{
        .ally = ally,
        .clock = clock,
        .system = rt.System{
            .clock = clock.clock(),
            .rng = std.crypto.random,
        },
        .indices = std.StringHashMap(usize).init(ally),
        .edges = std.ArrayList(std.AutoHashMap(usize, void)).init(ally),
        .nodes = std.ArrayList(Node).init(ally),
    };

    inline for (std.meta.fields(@TypeOf(topology))) |node_field| {
        const node = @field(topology, node_field.name);
        // TODO: Allow for specifying some fields and defaulting others.
        const node_options: rt.Node.Options = if (@hasField(@TypeOf(node), "options")) {
            node.options;
        } else {
            .{};
        };

        const framework_node = try self.addNode(node_field.name, node_options);

        inline for (std.meta.fields((@TypeOf(node.interfaces)))) |interface_field| {
            const interface = @field(node.interfaces, interface_field.name);
            // TODO: Allow for specifying some fields and defaulting others.
            const interface_config: rt.Interface.Config = if (@hasField(@TypeOf(interface), "config")) {
                interface.config;
            } else {
                .{};
            };

            const framework_interface = Interface{
                .api = try framework_node.node.addInterface(interface_config),
                .config = interface_config,
                .to = std.StringHashMap(void).init(self.ally),
            };

            inline for (std.meta.fields((@TypeOf(interface.to)))) |target| {
                try framework_interface.to.put(target.name, {});
            }

            try framework_node.interfaces.put(interface_field.name, framework_interface);
        }
    }

    return self;
}

pub fn addNode(self: *Self, name: []const u8, options: rt.Node.Options) *rt.Node!void {
    if (self.nodes.contains(name)) {
        return Error.DuplicateName;
    }

    const node = Node{
        .node = try rt.Node.init(self.ally, self.system, options),
        .interfaces = std.StringHashMap(void).init(self.ally),
    };

    try self.nodes.put(name, node);

    return self.nodes.getPtr(name).?;
}

pub fn addEndpoint(self: *Self, name: []const u8) !rt.Endpoint {
    const identity = try rt.Identity.random(&self.system.rng);
    var builder = rt.endpoint.Builder.init(self.ally);
    _ = try builder
        .setIdentity(identity)
        .setDirection(.in)
        .setMethod(.single)
        .setApplicationName(name);
    var endpoint = try builder.build();

    if (self.indices.get(name)) |index| {
        var node = self.nodes.items[index];
        const endpoint_copy = try endpoint.copy();
        try node.endpoints.append(endpoint_copy);
    }

    return endpoint;
}

pub fn getNode(self: *Self, name: []const u8) ?*Node {
    const index = self.indices.get(name) orelse return null;
    return &self.nodes.items[index];
}

pub fn send(self: *Self, src: []const u8, dst: []const u8, data: []const u8) !void {
    const n1 = self.getNode(src) orelse return;
    const n2 = self.getNode(dst) orelse return;
    const e1 = n1.endpoints.getLast();
    const e2 = n2.endpoints.getLast();

    const packet = rt.packet.Builder.init(self.ally)
        .setTransport(e1.hash, e2.hash)
        .appendPayload(data)
        .build();

    try n1.api.send(packet);
}

pub fn process(self: *Self) !void {
    var indices = self.indices.valueIterator();
    while (indices.next()) |index| {
        var target = self.nodes.items[index.*];
        try target.node.process();
        while (target.api.collect(rt.unit.BitRate.default)) |packet| {
            var sources = self.edges.items[index.*].keyIterator();
            while (sources.next()) |k| {
                var connected = self.nodes.items[k.*];
                try connected.api.deliver(packet);
                try connected.node.process();
            }
        }
    }
}

pub fn collect(self: *Self, node_name: []const u8, interface_name: []const u8) !std.ArrayList(rt.Packet) {
    const packets = std.ArrayList(rt.Packet).init(self.ally);
    const node = self.getNode(node_name).?;
    const interface = node.interfaces.get(interface_name).?;

    while (interface.api.collect(rt.unit.BitRate.default)) |packet| {
        packets.put(packet);
    }

    return packets;
}
