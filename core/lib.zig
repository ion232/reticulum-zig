pub const crypto = @import("crypto.zig");
pub const endpoint = @import("endpoint.zig");
pub const packet = @import("packet.zig");
pub const unit = @import("unit.zig");

pub const Endpoint = endpoint.Managed;
pub const Identity = crypto.Identity;
pub const Packet = @import("Packet.zig");
pub const Interface = @import("Interface.zig");
pub const Node = @import("Node.zig");
pub const System = @import("System.zig");

comptime {
    const builtin = @import("builtin");
    const std = @import("std");

    // We import the file so that the exports actually run for this module.
    _ = @import("exports.zig");

    // Ensure unit tests are ran by referencing relevant files.
    // TODO: I think there was a better way of doing this.
    if (builtin.is_test) {
        // Unused files must be specifically enumerated.
        std.testing.refAllDecls(@import("crypto/Aes.zig"));
        // Fernet currently needs fixing.
        // Public files can be referenced all at once from here.
        std.testing.refAllDecls(@This());
    }
}
