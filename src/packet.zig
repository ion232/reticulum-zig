const std = @import("std");

pub const Header = packed struct {
    pub const Flag = struct {
        pub const Ifac = enum(u1) {
            open,
            auth,
        };

        pub const Type = enum(u1) {
            one,
            two,
        };

        pub const Context = enum(u1) {
            off,
            on,
        };

        pub const Propagation = enum(u1) {
            broadcast,
            transport,
        };

        pub const Destination = enum(u2) {
            single,
            group,
            plain,
            link,
        };

        pub const Packet = enum(u2) {
            data,
            announce,
            link_request,
            proof,
        };
    };

    ifac: Flag.Ifac,
    type: Flag.Type,
    context: Flag.Context,
    propagation: Flag.Propagation,
    destination: Flag.Destination,
    purpose: Flag.Packet,
    hops: u8,
};

pub const AddressSize = 16;
pub const Address = [AddressSize]u8;

pub const Packet = struct {
    header: Header,
    ifac: ?[]const u8,
    address: Address,
    other_address: ?Address,
    context: u8,
    data: []const u8,
};
