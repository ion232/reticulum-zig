const std = @import("std");
const crypto = @import("crypto.zig");
const data = @import("data.zig");
const endpoint = @import("endpoint.zig");

const Allocator = std.mem.Allocator;
const Endpoint = endpoint.Managed;
const Hash = crypto.Hash;
const Identity = crypto.Identity;

pub const Builder = @import("packet/Builder.zig");
pub const Factory = @import("packet/Factory.zig");
pub const Filter = @import("packet/Filter.zig");
pub const Managed = @import("packet/Managed.zig");
pub const Packet = Managed;

pub const Payload = union(enum) {
    const Self = @This();

    pub const Announce = struct {
        pub const Noise = [5]u8;
        pub const Timestamp = u40;
        pub const minimum_size = blk: {
            var total = 0;
            total += crypto.X25519.public_length;
            total += crypto.Ed25519.PublicKey.encoded_length;
            total += crypto.Hash.name_length;
            total += @sizeOf(Noise);
            total += @sizeOf(Timestamp);
            total += crypto.Ed25519.Signature.encoded_length;
            break :blk total;
        };

        public: Identity.Public,
        name_hash: Hash.Name,
        noise: Noise,
        timestamp: Timestamp,
        ratchet: ?crypto.Identity.Ratchet,
        signature: crypto.Ed25519.Signature,
        application_data: data.Bytes,
    };

    announce: Announce,
    raw: data.Bytes,
    none,

    pub fn makeRaw(bytes: data.Bytes) Self {
        return Self{
            .raw = bytes,
        };
    }

    pub fn clone(self: Self) !Self {
        return switch (self) {
            .announce => |a| Self{
                .announce = Announce{
                    .public = a.public,
                    .name_hash = a.name_hash,
                    .noise = a.noise,
                    .timestamp = a.timestamp,
                    .ratchet = a.ratchet,
                    .signature = a.signature,
                    .application_data = try a.application_data.clone(),
                },
            },
            .raw => |r| Self{
                .raw = try r.clone(),
            },
            .none => Self.none,
        };
    }

    pub fn size(self: *const Self) usize {
        return switch (self.*) {
            .announce => |*a| blk: {
                var total: usize = 0;
                total += crypto.X25519.public_length;
                total += crypto.Ed25519.PublicKey.encoded_length;
                total += crypto.Hash.name_length;
                total += @sizeOf(Announce.Noise);
                total += @sizeOf(Announce.Timestamp);
                total += if (a.ratchet != null) @sizeOf(crypto.Identity.Ratchet) else 0;
                total += crypto.Ed25519.Signature.encoded_length;
                total += a.application_data.items.len;
                break :blk total;
            },
            .raw => |*r| r.items.len,
            .none => 0,
        };
    }

    pub fn deinit(self: *Self) void {
        return switch (self.*) {
            .announce => |*announce| announce.application_data.deinit(),
            .raw => |*raw| raw.deinit(),
            .none => {},
        };
    }
};

pub const Endpoints = union(Header.Flag.Format) {
    const Self = @This();

    pub const Normal = struct {
        endpoint: Hash.Short,
    };

    pub const Transport = struct {
        transport_id: Hash.Short,
        endpoint: Hash.Short,
    };

    normal: Normal,
    transport: Transport,

    pub fn endpoint(self: Self) Hash.Short {
        return switch (self) {
            .normal => |n| n.endpoint,
            .transport => |t| t.endpoint,
        };
    }

    pub fn nextHop(self: Self) Hash.Short {
        return switch (self) {
            .normal => |n| n.endpoint,
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

        pub const Format = enum(u1) {
            normal,
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

        pub const Endpoint = endpoint.Variant;

        pub const Purpose = enum(u2) {
            data,
            announce,
            link_request,
            proof,
        };
    };

    purpose: Flag.Purpose = .data,
    endpoint: Flag.Endpoint = .single,
    propagation: Flag.Propagation = .broadcast,
    context: Flag.Context = .none,
    format: Flag.Format = .normal,
    interface: Flag.Interface = .open,
    hops: u8 = 0,
};

pub const Context = enum(u8) {
    none = 0,
    resource,
    resource_advertisement,
    resource_request,
    resource_hashmap_update,
    resource_proof,
    resource_initiator_cancel,
    resource_receiver_cancel,
    cache_request,
    request,
    response,
    path_response,
    command,
    command_status,
    link_channel,
    keep_alive = 250,
    link_identify,
    link_close,
    link_proof,
    link_request_rtt,
    link_request_proof,
};

test "validate-raw-announce-roundtrip" {
    const t = std.testing;
    const ally = t.allocator;
    const rng = std.crypto.random;

    // Captured from reference implementation - with framing removed.
    const raw_announce = "71008133c7ce6d6be9b4070a3b98ee9ecab583dfe79d30200ee5e9f5c5615d45a5b000fb266456840e5f4d010a6fbb4025969f8db5415597e3d7a48431d0534e441d0bdeb78f1064f50b447291dd51617040dc9c40cb5b9adab1314ad270b1297d6fd46ec60bc318e2c0f0d908fc1c2bcdef00686f9b4ef17ec1b73f60b14df6709cb74164bd1890e26ff8a4634bbd855051ef959f413d7f7c8f9ff0f54ee81fb994c4e1975fe6f4b56fb26d2e107bd824d864a6932a2e2c02b1352ad9a31ce1cbeae72902effef1ccdeb7d004fbe527cd39111dc59d0e92c406696f6e323332c0";

    var bytes = std.ArrayList(u8).init(ally);
    defer bytes.deinit();

    var i: usize = 0;
    while (i < raw_announce.len) : (i += 2) {
        const byte = std.fmt.parseInt(u8, raw_announce[i .. i + 2], 16) catch break;
        try bytes.append(byte);
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
    defer raw_bytes.deinit();
    const raw_packet = try announce_packet.write(raw_bytes.items);

    var p = try factory.fromBytes(raw_packet);
    defer p.deinit();

    try t.expect(p.header.purpose == .announce);
    try p.validate();

    const announce = p.payload.announce;
    try t.expectEqualStrings(app_data, announce.application_data.items);
}
