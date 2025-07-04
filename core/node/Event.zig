const std = @import("std");
const data = @import("../data.zig");
const endpoint = @import("../endpoint.zig");
const Packet = @import("../packet.zig").Managed;
const Payload = @import("../packet.zig").Payload;
const Hash = @import("../crypto/Hash.zig");

// TODO: Perhaps distinguish between tasks and packets.

pub const In = union(enum) {
    announce: Announce,
    packet: Packet,
    plain: Plain,

    pub const Announce = struct {
        hash: Hash,
        app_data: ?data.Bytes,
    };

    pub const Plain = struct {
        name: endpoint.Name,
        payload: Payload,
    };

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .announce => |*announce| {
                if (announce.app_data) |app_data| {
                    app_data.deinit();
                }
            },
            .packet => |*packet| {
                packet.deinit();
            },
            .plain => |*plain| {
                plain.name.deinit();
                plain.payload.deinit();
            },
        }
    }
};

pub const Out = union(enum) {
    packet: Packet,

    pub fn deinit(self: *@This()) void {
        switch (self.*) {
            .packet => |*packet| {
                packet.deinit();
            },
        }
    }

    // TODO: Replace this with a cleaner implementation.
    pub fn format(this: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, w: anytype) !void {
        _ = fmt;
        _ = options;

        const F = struct {
            const Self = @This();

            writer: @TypeOf(w),
            indentation: u8 = 0,

            fn init(writer: @TypeOf(w)) Self {
                return .{
                    .writer = writer,
                };
            }

            fn indent(self: *Self) !void {
                for (0..self.indentation) |_| {
                    try self.writer.print(" ", .{});
                }
            }

            fn entry(self: *Self, key: []const u8, comptime value_fmt: []const u8, args: anytype) !void {
                try self.indent();
                try self.writer.print(".{s} = ", .{key});
                try self.writer.print(value_fmt ++ ",\n", args);
            }

            fn objectStart(self: *Self, key: []const u8, tag: []const u8) !void {
                try self.indent();
                try self.writer.print(".{s} = .{s}{{\n", .{ key, tag });
                self.indentation += 2;
            }

            fn objectEnd(self: *Self) !void {
                self.indentation -= 2;
                try self.indent();
                try self.writer.print("}},\n", .{});
            }

            fn print(self: *Self, comptime text: []const u8, args: anytype) !void {
                try self.writer.print(text, args);
            }
        };

        const hex = std.fmt.fmtSliceHexLower;
        var f = F.init(w);

        switch (this) {
            .packet => |p| {
                try f.objectStart("packet", "");

                const h = p.header;
                try f.entry("header", ".{{.{s}, .{s}, .{s}, .{s}, .{s}, .{s}, hops({d})}}", .{
                    @tagName(h.interface),
                    @tagName(h.format),
                    @tagName(h.context),
                    @tagName(h.propagation),
                    @tagName(h.method),
                    @tagName(h.purpose),
                    h.hops,
                });

                if (p.interface_access_code.items.len > 0) {
                    try f.entry("interface_access_code", "{x}", .{hex(p.interface_access_code.items)});
                }

                switch (p.endpoints) {
                    .normal => |n| {
                        try f.entry("endpoints", ".normal{{{x}}}", .{
                            hex(&n.endpoint),
                        });
                    },
                    .transport => |t| {
                        try f.entry("endpoints", ".transport{{{x}, {x}}}", .{
                            hex(&t.endpoint),
                            hex(&t.transport_id),
                        });
                    },
                }

                try f.entry("context", ".{s}", .{@tagName(p.context)});

                switch (p.payload) {
                    .announce => |a| {
                        try f.objectStart("payload", "announce");

                        try f.entry("public.dh", "{x}", .{hex(&a.public.dh)});
                        try f.entry("public.signature", "{x}", .{hex(&a.public.signature.bytes)});
                        try f.entry("name_hash", "{x}", .{hex(&a.name_hash)});
                        try f.entry("noise", "{x}", .{hex(&a.noise)});
                        try f.entry("timestamp", "{}", .{a.timestamp});
                        try f.entry("signature", "{x}", .{hex(&a.signature.toBytes())});

                        if (a.application_data.items.len > 0) {
                            try f.entry("application_data", "{x}", .{hex(a.application_data.items)});
                        }

                        try f.objectEnd();
                    },
                    .raw => |r| {
                        try f.entry("payload", ".raw{{{x}}}", .{hex(r.items)});
                    },
                    .none => {
                        try f.entry("payload", ".none", .{});
                    },
                }

                f.indentation -= 2;
                try f.indent();
                try f.print("}}", .{});
            },
        }
    }
};
