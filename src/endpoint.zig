pub const Identity = @import("identity.zig").Identity;
pub const manager = @import("manager.zig");

pub const Endpoint = struct {
    identity: Identity,

    // ion232: Can't call this identity because it shadows the import.
    pub fn init(id: Identity) Endpoint {
        return .{
            .identity = id,
        };
    }
};

pub const Direction = enum {
    in,
    out,
};

pub const Type = enum {
    plain,
    single,
    group,
    link,
};
