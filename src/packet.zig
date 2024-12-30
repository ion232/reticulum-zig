const std = @import("std");
const crypto = @import("crypto.zig");

const Allocator = std.mem.Allocator;
const Bytes = std.ArrayList(u8);
const Endpoint = @import("endpoint.zig").Managed;
const EndpointMethod = @import("endpoint.zig").Method;
const Hash = crypto.Hash;
const Identity = crypto.Identity;

pub const Builder = @import("packet/Builder.zig");
pub const Factory = @import("packet/Factory.zig");
pub const Managed = @import("packet/Managed.zig");
pub const Packet = Managed;

pub const Payload = union(enum) {
    pub const Announce = struct {
        pub const Noise = [5]u8;
        pub const Timestamp = u40;

        public: Identity.Public,
        name_hash: Hash.Name,
        noise: Noise,
        timestamp: Timestamp,
        // rachet: ?*const [N]u8,
        signature: crypto.Ed25519.Signature,
        application_data: Bytes,
    };

    announce: Announce,
    raw: Bytes,
    none,
};

pub const Endpoints = union(Header.Flag.Format) {
    const Self = @This();

    pub const Normal = packed struct {
        endpoint: Hash.Short,
    };

    pub const Transport = packed struct {
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

    pub fn next_hop(self: Self) Hash.Short {
        return switch (self) {
            .normal => |n| n.endpoint,
            .transport => |t| t.transport_id,
        };
    }
};

pub const Header = packed struct {
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
            set,
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

    interface: Flag.Interface,
    format: Flag.Format,
    context: Flag.Context,
    propagation: Flag.Propagation,
    method: Flag.Method,
    purpose: Flag.Purpose,
    hops: u8,
};

pub const Context = enum(u8) {
    none,
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

test "Header size" {
    try std.testing.expect(@sizeOf(Header) == 2);
}
