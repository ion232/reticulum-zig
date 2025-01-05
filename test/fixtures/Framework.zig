const std = @import("std");
const rt = @import("reticulum");

const Allocator = std.mem.Allocator;
const Clock = @import("Clock.zig");

pub const Error = error{
    UnknownName,
    DuplicateName,
} || Allocator.Error;

const Node = struct {
    node: rt.Node,
    endpoints: std.ArrayList(rt.Endpoint),
    api: rt.Interface.Api,
};

const Self = @This();

ally: Allocator,
options: rt.Node.Options,
clock: Clock,
system: rt.System,
indices: std.StringHashMap(usize),
edges: std.ArrayList(std.AutoHashMap(usize, void)),
nodes: std.ArrayList(Node),

pub fn init(ally: Allocator, options: rt.Node.Options) Self {
    var clock = Clock.init();

    return Self{
        .ally = ally,
        .options = options,
        .clock = clock,
        .system = rt.System{
            .clock = clock.clock(),
            .rng = std.crypto.random,
        },
        .indices = std.StringHashMap(usize).init(ally),
        .edges = std.ArrayList(std.AutoHashMap(usize, void)).init(ally),
        .nodes = std.ArrayList(Node).init(ally),
    };
}

pub fn addEndpoint(self: *Self, name: []const u8) !rt.Endpoint {
    const identity = try rt.Identity.random(&self.system.rng);
    var builder = rt.endpoint.Builder.init(self.ally);
    _ = try builder
        .set_identity(identity)
        .set_direction(.in)
        .set_method(.single)
        .set_application_name(name);
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
        .set_transport(e1.hash, e2.hash)
        .append_payload(data)
        .build();

    try n1.api.send(packet);
}

pub fn process(self: *Self) !void {
    var indices = self.indices.valueIterator();
    while (indices.next()) |index| {
        var target = self.nodes.items[index.*];
        try target.node.process();
        while (target.api.collect(rt.units.BitRate.default)) |packet| {
            var keys = self.edges.items[index.*].keyIterator();
            while (keys.next()) |k| {
                var connected = self.nodes.items[k.*];
                try connected.api.deliver(packet);
                try connected.node.process();
            }
        }
    }
}

pub fn addNode(self: *Self, name: []const u8) !void {
    if (self.indices.contains(name)) {
        return Error.DuplicateName;
    }

    const index = self.indices.count();
    try self.indices.put(name, index);
    try self.edges.append(std.AutoHashMap(usize, void).init(self.ally));

    var node = try rt.Node.init(self.ally, self.system, self.options);
    const api = try node.addInterface(.{});

    try self.nodes.append(Node{
        .node = node,
        .endpoints = std.ArrayList(rt.Endpoint).init(self.ally),
        .api = api,
    });
}

pub fn connect(self: *Self, a: []const u8, b: []const u8) !void {
    const a_index = self.indices.get(a) orelse return Error.UnknownName;
    const b_index = self.indices.get(b) orelse return Error.UnknownName;

    try self.edges.items[a_index].put(b_index, {});
    try self.edges.items[b_index].put(a_index, {});
}
