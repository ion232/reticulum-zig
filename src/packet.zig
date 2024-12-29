const std = @import("std");
const Endpoint = @import("endpoint.zig").Managed;

const Allocator = std.mem.Allocator;
const Builder = @import("packet/Builder.zig");
const Packet = Managed;
const Managed = @import("packet/Managed.zig");
const Unmanaged = @import("packet/Unmanaged.zig");

pub fn announce(ally: Allocator, endpoint: Endpoint) !Packet {
    // Make the announce packet.
}

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
            off,
            on,
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
