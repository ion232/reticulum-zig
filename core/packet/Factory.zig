const std = @import("std");
const crypto = @import("../crypto.zig");
const data = @import("../data.zig");
const packet = @import("../packet.zig");

const Allocator = std.mem.Allocator;
const Rng = @import("../System.zig").Rng;
const Clock = @import("../System.zig").Clock;
const Interface = @import("../Interface.zig");
const Endpoint = @import("../endpoint.zig").Managed;
const Name = @import("../endpoint.zig").Name;
const Builder = @import("Builder.zig");
const Packet = @import("Managed.zig");

// TODO: This definitely all needs tidying up.

pub const Error = error{
    InvalidBytesLength,
    InvalidAuthentication,
    MissingIdentity,
} || crypto.Identity.Error || Builder.Error || Allocator.Error;

const Self = @This();

ally: Allocator,
rng: Rng,
config: Interface.Config,

pub fn init(ally: Allocator, rng: Rng, config: Interface.Config) Self {
    return Self{
        .ally = ally,
        .rng = rng,
        .config = config,
    };
}

pub fn fromBytes(self: *Self, bytes: []const u8) Error!Packet {
    //
}

pub fn makeAnnounce(self: *Self, endpoint: *const Endpoint, application_data: ?[]const u8, now: u64) Error!Packet {
    const identity = endpoint.identity orelse return Error.MissingIdentity;
    var announce: packet.Payload.Announce = undefined;

    announce.public = identity.public;
    announce.name_hash = endpoint.name.hash.name().*;
    self.rng.bytes(&announce.noise);
    announce.timestamp = @truncate(now);
    var ratchet: crypto.Identity.Ratchet = undefined;
    self.rng.bytes(&ratchet);
    announce.ratchet = ratchet;
    announce.application_data = data.Bytes.empty;

    if (application_data) |app_data| {
        try announce.application_data.appendSlice(self.ally, app_data);
    }

    announce.signature = blk: {
        var arena = std.heap.ArenaAllocator.init(self.ally);
        defer arena.deinit();

        const arena_allocator = arena.allocator();
        var bytes = data.Bytes.empty;
        try bytes.appendSlice(arena_allocator, endpoint.hash.short());
        try bytes.appendSlice(arena_allocator, announce.public.dh[0..]);
        try bytes.appendSlice(arena_allocator, announce.public.signature.bytes[0..]);
        try bytes.appendSlice(arena_allocator, announce.name_hash[0..]);
        try bytes.appendSlice(arena_allocator, announce.noise[0..]);
        var timestamp_bytes: [5]u8 = undefined;
        std.mem.writeInt(u40, &timestamp_bytes, announce.timestamp, .big);
        try bytes.appendSlice(arena_allocator, &timestamp_bytes);

        if (announce.ratchet) |*r| {
            try bytes.appendSlice(arena_allocator, r[0..]);
        }

        try bytes.appendSlice(arena_allocator, announce.application_data.items);

        break :blk try identity.sign(bytes);
    };

    var builder = Builder.init(self.ally);

    if (self.config.access_code) |interface_access_code| {
        _ = try builder.setInterfaceAccessCode(interface_access_code);
    }

    return try builder
        .setEndpoint(endpoint.hash.short().*)
        .setPayload(.{ .announce = announce })
        .build();
}

pub fn makePlain(self: *Self, name: Name, payload: packet.Payload) Error!Packet {
    var builder = Builder.init(self.ally);

    if (self.config.access_code) |interface_access_code| {
        _ = try builder.setInterfaceAccessCode(interface_access_code);
    }

    const plain = try builder
        .setVariant(.plain)
        .setEndpoint(name.hash.short().*)
        .setPayload(payload)
        .build();

    return plain;
}
