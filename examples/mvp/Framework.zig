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
    api: rt.interface.Engine.Api,
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
    const clock = Clock.init();
    const rng = rt.System.Os.Rng.init();

    return Self{
        .ally = ally,
        .options = options,
        .clock = clock,
        .system = rt.System{
            .clock = clock.clock(),
            .rng = rng.rng(),
        },
        .indices = std.StringHashMap(usize).init(ally),
        .edges = std.ArrayList(std.AutoHashMap(usize, void)).init(ally),
        .nodes = std.ArrayList(Node).init(ally),
    };
}

pub fn add_endpoint(self: *Self, name: []const u8) ?rt.Endpoint {
    const endpoint = try rt.endpoint.Builder.init(self.ally)
        .set_identity(rt.Identity.random(&self.system.rng))
        .set_direction(.in)
        .set_method(.single)
        .set_application_name(name)
        .build();

    if (self.indices.get(name)) |index| {
        const node = self.nodes.items[index];
        node.endpoints.append(endpoint);
    }

    return endpoint;
}

pub fn get_node(self: *Self, name: []const u8) ?*Node {
    const index = self.indices.get(name) orelse return null;
    return &self.nodes.items[index];
}

pub fn send(self: *Self, src: []const u8, dst: []const u8, data: []const u8) !void {
    const n1 = self.get_node(src) orelse return;
    const n2 = self.get_node(dst) orelse return;
    const e1 = n1.endpoints.getLast();
    const e2 = n2.endpoints.getLast();

    const packet = rt.packet.Builder.init(self.ally)
        .set_transport(e1.hash, e2.hash)
        .append_payload(data)
        .build();

    try n1.api.send(packet);
}

pub fn process(self: *Self) !void {
    const indices = self.indices.valueIterator();
    while (indices.next()) |index| {
        const target = self.nodes.items[index.*];
        target.node.process();
        while (target.api.collect()) |packet| {
            const keys = self.edges.items[index.*].keyIterator();
            while (keys.next()) |k| {
                const connected = self.nodes.items[k.*];
                connected.api.deliver(packet);
                connected.node.process();
            }
        }
    }
}

pub fn add_node(self: *Self, name: []const u8) !*Node {
    if (self.indices.contains(name)) {
        return Error.DuplicateName;
    }

    const index = self.indices.count();
    try self.indices.put(name, index);
    try self.edges.append(std.AutoHashMap(usize, void).init(self.ally));

    const node = try rt.Node.init(self.ally, self.system, self.options);
    try self.nodes.append(Node{
        .node = node,
        .endpoints = std.ArrayList(rt.Endpoint).init(self.ally),
        .api = try node.addInterface(.{}),
    });

    return &self.nodes.items[index];
}

pub fn connect(self: *Self, a: []const u8, b: []const u8) !void {
    const a_index = self.indices.get(a) orelse return Error.UnknownName;
    const b_index = self.indices.get(b) orelse return Error.UnknownName;

    try self.edges.items[a_index].put(b_index);
    try self.edges.items[b_index].put(a_index);
}
