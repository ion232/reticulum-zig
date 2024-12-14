pub const identity = @import("identity.zig");
pub const manager = @import("manager.zig");

pub const Identity = identity.Identity;

pub const Endpoint = struct {
    identity: Identity,

    // ion232: Can't call this identity because it shadows import.
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
