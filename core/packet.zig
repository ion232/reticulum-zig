const std = @import("std");
const crypto = @import("crypto.zig");
const data = @import("data.zig");

const Allocator = std.mem.Allocator;
const Endpoint = @import("endpoint.zig").Managed;
const EndpointMethod = @import("endpoint.zig").Method;
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
        // rachet: ?*const [N]u8,
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
        return switch (self) {
            .announce => |*a| blk: {
                var total: usize = 0;
                total += crypto.X25519.public_length;
                total += crypto.Ed25519.PublicKey.encoded_length;
                total += crypto.Hash.name_length;
                total += @sizeOf(Announce.Noise);
                total += @sizeOf(Announce.Timestamp);
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

        pub const Method = EndpointMethod;

        pub const Purpose = enum(u2) {
            data,
            announce,
            link_request,
            proof,
        };
    };

    interface: Flag.Interface = .open,
    format: Flag.Format = .normal,
    context: Flag.Context = .none,
    propagation: Flag.Propagation = .broadcast,
    method: Flag.Method = .single,
    purpose: Flag.Purpose = .data,
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
