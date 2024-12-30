const std = @import("std");

const Allocator = std.mem.Allocator;
const Endpoint = @import("endpoint.zig").Managed;
const EndpointMethod = @import("endpoint.zig").Method;

pub const Builder = @import("packet/Builder.zig");
pub const Managed = @import("packet/Managed.zig");
pub const Packet = Managed;

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
