const adt = @import("../adt.zig");
const std = @import("std");

const Packet = @import("../Packet.zig");
const EndpointsTag = Packet.Header.Flag.Endpoints;
const PayloadTag = Packet.PayloadTag;

pub const Builder = @import("Storage/Builder.zig");

pub const Error = error{
    FailedToParse,
    OutOfMemory,
} || Builder.Error;

pub const Handle = struct {
    ptr: *Packet.Buffer,
};

const Self = @This();

pool: adt.Pool(Packet.Buffer),

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .pool = .init(allocator),
    };
}

pub fn builder(self: *Self) error{OutOfMemory}!Builder {
    const handle = try self.create();
    return .init(handle);
}

pub fn build(self: *Self, builder: Builder) Error!Packet.View {
    const data = try builder.result();
}

pub fn store(raw_bytes: []const u8) Error!Packet.View {
    const parser = Packet.Parser;
}

fn allocate(self: *Self) error{OutOfMemory}!Handle {
    const buffer = try self.pool.create();
    return .{ .ptr = buffer };
}

test "validate-raw-announce-roundtrip" {
    const t = std.testing;
    const ally = t.allocator;
    const rng = std.crypto.random;

    // Captured from reference implementation - with framing removed.
    const raw_announce = "71008133c7ce6d6be9b4070a3b98ee9ecab583dfe79d30200ee5e9f5c5615d45a5b000fb266456840e5f4d010a6fbb4025969f8db5415597e3d7a48431d0534e441d0bdeb78f1064f50b447291dd51617040dc9c40cb5b9adab1314ad270b1297d6fd46ec60bc318e2c0f0d908fc1c2bcdef00686f9b4ef17ec1b73f60b14df6709cb74164bd1890e26ff8a4634bbd855051ef959f413d7f7c8f9ff0f54ee81fb994c4e1975fe6f4b56fb26d2e107bd824d864a6932a2e2c02b1352ad9a31ce1cbeae72902effef1ccdeb7d004fbe527cd39111dc59d0e92c406696f6e323332c0";

    var bytes = std.ArrayList(u8).empty;
    defer bytes.deinit(ally);

    var i: usize = 0;
    while (i < raw_announce.len) : (i += 2) {
        const byte = std.fmt.parseInt(u8, raw_announce[i .. i + 2], 16) catch break;
        try bytes.append(ally, byte);
    }

    var factory = Factory.init(ally, rng, .{});
    var p = try factory.fromBytes(bytes.items);
    defer p.deinit();

    try t.expect(p.header.purpose == .announce);
    try t.expect(p.header.context == .some);
    try t.expect(p.payload.announce.ratchet != null);

    try p.validate();

    var buffer: [1024]u8 = undefined;

    var q = try factory.fromBytes(try p.write(&buffer));
    defer q.deinit();

    try t.expect(q.header.purpose == .announce);
    try t.expect(q.header.context == .some);
    try t.expect(q.payload.announce.ratchet != null);

    try q.validate();
}

test "validate-make-announce" {
    const t = std.testing;
    const ally = t.allocator;
    var rng = std.crypto.random;

    var builder = endpoint.Builder.init(ally);
    defer builder.deinit();

    var announce_endpoint = try builder
        .setIdentity(try crypto.Identity.random(&rng))
        .setDirection(.in)
        .setVariant(.single)
        .setName(try endpoint.Name.init("endpoint", &.{"test"}, ally))
        .build();
    defer announce_endpoint.deinit();

    const app_data = "some application data";
    const now = 123456789;
    var factory = Factory.init(ally, rng, .{});
    var announce_packet = try factory.makeAnnounce(&announce_endpoint, app_data, now);
    defer announce_packet.deinit();

    var raw_bytes = try data.Bytes.initCapacity(ally, announce_packet.size());
    raw_bytes.expandToCapacity();
    defer raw_bytes.deinit(ally);
    const raw_packet = try announce_packet.write(raw_bytes.items);

    var p = try factory.fromBytes(raw_packet);
    defer p.deinit();

    try t.expect(p.header.purpose == .announce);
    try p.validate();

    const announce = p.payload.announce;
    try t.expectEqualStrings(app_data, announce.application_data.items);
}
