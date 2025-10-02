const std = @import("std");
const data = @import("../data.zig");
const endpoint = @import("../endpoint.zig");
const Packet = @import("../packet.zig").Managed;
const Payload = @import("../packet.zig").Payload;
const Hash = @import("../crypto/Hash.zig");

const Allocator = std.mem.Allocator;

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

    pub fn deinit(self: *@This(), ally: Allocator) void {
        switch (self.*) {
            .announce => |*announce| {
                if (announce.app_data) |*app_data| {
                    app_data.deinit(ally);
                }
            },
            .packet => |*packet| {
                packet.deinit();
            },
            .plain => |*plain| {
                plain.name.deinit();
                plain.payload.deinit(ally);
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
    pub fn format(this: @This(), writer: *std.Io.Writer) !void {
        const F = struct {
            const Self = @This();

            io_writer: *std.Io.Writer,
            indentation: u8 = 0,

            fn init(io_writer: *std.Io.Writer) Self {
                return .{
                    .io_writer = io_writer,
                };
            }

            fn indent(self: *Self) !void {
                for (0..self.indentation) |_| {
                    try self.io_writer.print(" ", .{});
                }
            }

            fn entry(self: *Self, key: []const u8, comptime value_fmt: []const u8, args: anytype) !void {
                try self.indent();
                try self.io_writer.print(".{s} = ", .{key});
                try self.io_writer.print(value_fmt ++ ",\n", args);
            }

            fn objectStart(self: *Self, key: []const u8, tag: []const u8) !void {
                try self.indent();
                try self.io_writer.print(".{s} = .{s}{{\n", .{ key, tag });
                self.indentation += 2;
            }

            fn objectEnd(self: *Self) !void {
                self.indentation -= 2;
                try self.indent();
                try self.io_writer.print("}},\n", .{});
            }

            fn print(self: *Self, comptime text: []const u8, args: anytype) !void {
                try self.io_writer.print(text, args);
            }
        };

        var f = F.init(writer);

        switch (this) {
            .packet => |p| {
                try f.objectStart("packet", "");

                const h = p.header;
                try f.entry("header", ".{{.{s}, .{s}, .{s}, .{s}, .{s}, .{s}, hops({d})}}", .{
                    @tagName(h.interface),
                    @tagName(h.format),
                    @tagName(h.context),
                    @tagName(h.propagation),
                    @tagName(h.endpoint),
                    @tagName(h.purpose),
                    h.hops,
                });

                if (p.interface_access_code.items.len > 0) {
                    try f.entry("interface_access_code", "{x}", .{p.interface_access_code.items});
                }

                switch (p.endpoints) {
                    .normal => |n| {
                        try f.entry("endpoints", ".normal{{{x}}}", .{
                            &n.endpoint,
                        });
                    },
                    .transport => |t| {
                        try f.entry("endpoints", ".transport{{{x}, {x}}}", .{
                            &t.endpoint,
                            &t.transport_id,
                        });
                    },
                }

                try f.entry("context", ".{s}", .{@tagName(p.context)});

                switch (p.payload) {
                    .announce => |a| {
                        try f.objectStart("payload", "announce");

                        try f.entry("public.dh", "{x}", .{&a.public.dh});
                        try f.entry("public.signature", "{x}", .{&a.public.signature.bytes});
                        try f.entry("name_hash", "{x}", .{&a.name_hash});
                        try f.entry("noise", "{x}", .{&a.noise});
                        var timestamp_bytes: [5]u8 = undefined;
                        std.mem.writeInt(u40, &timestamp_bytes, a.timestamp, .big);
                        try f.entry("timestamp", "{x}", .{&timestamp_bytes});
                        if (a.ratchet) |*ratchet| {
                            try f.entry("ratchet", "{x}", .{ratchet});
                        }
                        try f.entry("signature", "{x}", .{&a.signature.toBytes()});

                        if (a.application_data.items.len > 0) {
                            try f.entry("application_data", "{x}", .{a.application_data.items});
                        }

                        try f.objectEnd();
                    },
                    .raw => |r| {
                        try f.entry("payload", ".raw{{{x}}}", .{r.items});
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
