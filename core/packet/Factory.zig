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
    var index: usize = 0;
    const header_size = @sizeOf(packet.Header);

    if (bytes.len < index + header_size) {
        return Error.InvalidBytesLength;
    }

    const header: packet.Header = @bitCast(bytes[0..header_size].*);
    index += header_size;

    const both_auth = self.config.access_code != null and header.interface == .authenticated;
    const both_open = self.config.access_code == null and header.interface == .open;

    if (!(both_auth or both_open)) {
        return Error.InvalidAuthentication;
    }

    var interface_access_code = data.Bytes.init(self.ally);
    errdefer interface_access_code.deinit();

    if (self.config.access_code) |access_code| {
        if (bytes.len < index + access_code.len) {
            return Error.InvalidBytesLength;
        }

        // TODO: I need to decrypt the packet here.

        try interface_access_code.appendSlice(bytes[index .. index + access_code.len]);
        index += access_code.len;
    }

    const endpoints_size: usize = switch (header.format) {
        .normal => @sizeOf(packet.Endpoints.Normal),
        .transport => @sizeOf(packet.Endpoints.Transport),
    };

    if (bytes.len < index + endpoints_size) {
        return Error.InvalidBytesLength;
    }

    const endpoints = switch (header.format) {
        .normal => blk: {
            var endpoint: crypto.Hash.Short = undefined;
            @memcpy(&endpoint, bytes[index .. index + endpoint.len]);
            index += endpoint.len;

            const endpoints = packet.Endpoints{
                .normal = .{
                    .endpoint = endpoint,
                },
            };

            break :blk endpoints;
        },
        .transport => blk: {
            var transport_id: crypto.Hash.Short = undefined;
            @memcpy(&transport_id, bytes[index .. index + transport_id.len]);
            index += transport_id.len;

            var endpoint: crypto.Hash.Short = undefined;
            @memcpy(&endpoint, bytes[index .. index + endpoint.len]);
            index += endpoint.len;

            const endpoints = packet.Endpoints{ .transport = .{
                .transport_id = transport_id,
                .endpoint = endpoint,
            } };

            break :blk endpoints;
        },
    };

    const context_size = @sizeOf(packet.Context);

    if (bytes.len < index + context_size) {
        return Error.InvalidBytesLength;
    }

    // TODO: Figure out how to do this properly.
    const context: packet.Context = @enumFromInt(bytes[index .. index + context_size][0]);
    index += context_size;

    const payload: packet.Payload = switch (header.purpose) {
        .announce => .{
            .announce = blk: {
                const Announce = packet.Payload.Announce;
                const Signature = crypto.Ed25519.Signature;

                var announce: Announce = undefined;

                if (bytes.len < index + Announce.minimum_size) {
                    return Error.InvalidBytesLength;
                }

                @memcpy(&announce.public.dh, bytes[index .. index + announce.public.dh.len]);
                index += announce.public.dh.len;
                var signature_key_bytes: [crypto.Ed25519.PublicKey.encoded_length]u8 = undefined;
                @memcpy(&signature_key_bytes, bytes[index .. index + signature_key_bytes.len]);
                announce.public.signature = try crypto.Ed25519.PublicKey.fromBytes(signature_key_bytes);
                index += signature_key_bytes.len;
                @memcpy(&announce.name_hash, bytes[index .. index + announce.name_hash.len]);
                index += announce.name_hash.len;
                @memcpy(&announce.noise, bytes[index .. index + 5]);
                index += 5;
                announce.timestamp = std.mem.readInt(u40, bytes[index .. index + 5][0..5], .big);
                index += 5;

                if (header.context == .some) {
                    var ratchet: [32]u8 = undefined;
                    @memcpy(&ratchet, bytes[index .. index + 32]);
                    announce.ratchet = ratchet;
                    index += 32;
                } else {
                    announce.ratchet = null;
                }

                var signature_bytes: [Signature.encoded_length]u8 = undefined;
                @memcpy(&signature_bytes, bytes[index .. index + Signature.encoded_length]);
                announce.signature = Signature.fromBytes(signature_bytes);
                index += Signature.encoded_length;

                var application_data = data.Bytes.init(self.ally);
                try application_data.appendSlice(bytes[index..]);
                announce.application_data = application_data;

                break :blk announce;
            },
        },
        else => .{ .raw = blk: {
            var raw = data.Bytes.init(self.ally);
            errdefer raw.deinit();
            try raw.appendSlice(bytes[index..]);
            break :blk raw;
        } },
    };

    return Packet{
        .ally = self.ally,
        .context = context,
        .endpoints = endpoints,
        .header = header,
        .interface_access_code = interface_access_code,
        .payload = payload,
    };
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
    announce.application_data = data.Bytes.init(self.ally);

    if (application_data) |app_data| {
        try announce.application_data.appendSlice(app_data);
    }

    announce.signature = blk: {
        var arena = std.heap.ArenaAllocator.init(self.ally);
        defer arena.deinit();

        var bytes = data.Bytes.init(arena.allocator());
        try bytes.appendSlice(endpoint.hash.short());
        try bytes.appendSlice(announce.public.dh[0..]);
        try bytes.appendSlice(announce.public.signature.bytes[0..]);
        try bytes.appendSlice(announce.name_hash[0..]);
        try bytes.appendSlice(announce.noise[0..]);
        var timestamp_bytes: [5]u8 = undefined;
        std.mem.writeInt(u40, &timestamp_bytes, announce.timestamp, .big);
        try bytes.appendSlice(&timestamp_bytes);

        if (announce.ratchet) |*r| {
            try bytes.appendSlice(r[0..]);
        }

        try bytes.appendSlice(announce.application_data.items);

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

pub fn makeData(self: *Self, name: Name, bytes: data.Bytes) Error!Packet {
    var builder = Builder.init(self.ally);

    if (self.config.access_code) |interface_access_code| {
        _ = try builder.setInterfaceAccessCode(interface_access_code);
    }

    return try builder
        .setVariant(.single)
        .setEndpoint(name.hash.short().*)
        .setPayload(packet.Payload.makeRaw(bytes))
        .build();
}

pub fn makePlain(self: *Self, name: Name, payload: packet.Payload) Error!Packet {
    var builder = Builder.init(self.ally);

    if (self.config.access_code) |interface_access_code| {
        _ = try builder.setInterfaceAccessCode(interface_access_code);
    }

    return try builder
        .setVariant(.plain)
        .setEndpoint(name.hash.short().*)
        .setPayload(payload)
        .build();
}
