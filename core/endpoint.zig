pub const Builder = @import("endpoint/Builder.zig");
pub const Managed = @import("endpoint/Managed.zig");
pub const Name = @import("endpoint/Name.zig");
pub const Store = @import("endpoint/Store.zig");

pub const Direction = enum {
    in,
    out,
};

pub const Variant = enum(u2) {
    single,
    group,
    plain,
    link,
};
