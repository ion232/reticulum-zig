pub const crypto = @import("crypto.zig");
pub const data = @import("data.zig");
pub const endpoint = @import("endpoint.zig");
pub const packet = @import("packet.zig");
pub const unit = @import("unit.zig");

pub const Endpoint = endpoint.Managed;
pub const Identity = crypto.Identity;
pub const Packet = packet.Packet;
pub const Interface = @import("Interface.zig");
pub const Node = @import("Node.zig");
pub const System = @import("System.zig");

comptime {
    const builtin = @import("builtin");
    const std = @import("std");

    // We import the file so that the exports actually run for this module.
    _ = @import("exports.zig");

    // Ensure unit tests are ran by referencing relevant files.
    if (builtin.is_test) {
        // Private files must be specifically enumerated.
        std.testing.refAllDecls(@import("crypto/Aes.zig"));
        std.testing.refAllDecls(@import("crypto/Fernet.zig"));
        std.testing.refAllDecls(@import("crypto/Identity.zig"));
        // Public files can be referenced all at once from here.
        std.testing.refAllDecls(@This());
    }
}
