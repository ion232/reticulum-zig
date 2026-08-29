const std = @import("std");
const crypto = @import("crypto.zig");
const endpoint = @import("endpoint.zig");

const Endpoint = endpoint.Managed;
const Hash = crypto.Hash;
const Identity = crypto.Identity;

pub const Builder = @import("packet/Builder.zig");
pub const Factory = @import("packet/Factory.zig");
pub const Filter = @import("Packet/Filter.zig");
pub const Storage = @import("Packet/Storage.zig");
pub const View = @import("Packet/View.zig");

pub const max_transmission_unit = 500;
pub const min_header = @sizeOf(Header) + @sizeOf(Endpoints) + @sizeOf(Context);
pub const max_payload_size = max_transmission_unit - min_header;

pub const Buffer = [max_transmission_unit]u8;
pub const AccessCode = []const u8;

pub const PayloadTag = enum { announce, raw, none };

pub const Endpoints = union(Header.Flag.Endpoints) {
    const Self = @This();

    pub const Single = packed struct {
        target: Hash.Short,
    };

    pub const Transport = packed struct {
        transport_id: Hash.Short,
        target: Hash.Short,
    };

    single: Single,
    transport: Transport,

    pub fn endpoint(self: Self) Hash.Short {
        return switch (self) {
            .single => |s| s.target,
            .transport => |t| t.endpoint,
        };
    }

    pub fn nextHop(self: Self) Hash.Short {
        return switch (self) {
            .single => |s| s.target,
            .transport => |t| t.transport_id,
        };
    }
};

pub const Header = packed struct(u16) {
    pub const Flag = struct {
        pub const Interface = enum(u1) {
            open,
            authenticated,
        };

        pub const Endpoints = enum(u1) {
            single,
            transport,
        };

        pub const Context = enum(u1) {
            none,
            some,
        };

        pub const Propagation = enum(u1) {
            broadcast,
            transport,
        };

        pub const Method = endpoint.Method;

        pub const Purpose = enum(u2) {
            data,
            announce,
            link_request,
            proof,
        };
    };

    purpose: Flag.Purpose = .data,
    method: Flag.Method = .datagram,
    propagation: Flag.Propagation = .broadcast,
    context: Flag.Context = .none,
    endpoints: Flag.Endpoints = .single,
    interface: Flag.Interface = .open,
    hops: u8 = 0,
};

pub const Context = enum(u8) {
    none = 0,
    resource = 1,
    resource_advertisement = 2,
    resource_request = 3,
    resource_hashmap_update = 4,
    resource_proof = 5,
    resource_initiator_cancel = 6,
    resource_receiver_cancel = 7,
    cache_request = 8,
    request = 9,
    response = 10,
    path_response = 11,
    command = 12,
    command_status = 13,
    link_channel = 14,
    keep_alive = 250,
    link_identify = 251,
    link_close = 252,
    link_proof = 253,
    link_request_rtt = 254,
    link_request_proof = 255,
};

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
