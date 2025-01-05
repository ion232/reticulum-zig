const std = @import("std");
const crypto = @import("../crypto.zig");
const packet = @import("../packet.zig");

const Allocator = std.mem.Allocator;
const Rng = @import("../System.zig").Rng;
const Clock = @import("../System.zig").Clock;
const Interface = @import("../Interface.zig");
const Bytes = std.ArrayList(u8);
const Endpoint = @import("../endpoint.zig").Managed;
const Builder = @import("Builder.zig");
const Packet = @import("Managed.zig");

// TODO: This definitely all needs tidying up.

pub const Error = error{
    InvalidBytesLength,
    InvalidAuthentication,
} || crypto.Identity.Error || Builder.Error || Allocator.Error;
const Self = @This();

ally: Allocator,
clock: Clock,
rng: Rng,
config: Interface.Config,

pub fn init(ally: Allocator, clock: Clock, rng: Rng, config: Interface.Config) Self {
    return Self{
        .ally = ally,
        .clock = clock,
        .rng = rng,
        .config = config,
    };
}

pub fn from_bytes(self: *Self, bytes: []const u8) Error!Packet {
    var index: usize = 0;
    const header_size = @sizeOf(packet.Header);

    if (bytes.len < index + header_size) {
        return Error.InvalidBytesLength;
    }

    const header: packet.Header = @bitCast(bytes[0..header_size].*);
    index += header_size;

    const both_auth = self.config.access_code != null and header.interface == .authenticated;
    const both_not_auth = self.config.access_code == null and header.interface == .open;
    const non_matching_auth = !both_auth or !both_not_auth;

    if (non_matching_auth) {
        return Error.InvalidAuthentication;
    }

    var interface_access_code = Bytes.init(self.ally);
    errdefer {
        interface_access_code.deinit();
    }

    if (self.config.access_code) |access_code| {
        if (bytes.len < index + access_code.len) {
            return Error.InvalidBytesLength;
        }

        // I need to decrypt the packet here.

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

            const endpoints = packet.Endpoints{ .normal = .{
                .endpoint = endpoint,
            } };

            break :blk endpoints;
        },
        .transport => blk: {
            var endpoint: crypto.Hash.Short = undefined;
            @memcpy(&endpoint, bytes[index .. index + endpoint.len]);
            index += endpoint.len;

            var transport_id: crypto.Hash.Short = undefined;
            @memcpy(&transport_id, bytes[index .. index + transport_id.len]);
            index += transport_id.len;

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
        .announce => .{ .announce = blk: {
            const Announce = packet.Payload.Announce;
            const Signature = crypto.Ed25519.Signature;
            var announce: Announce = undefined;

            if (bytes.len < index + Announce.minimum_size) {
                return Error.InvalidBytesLength;
            }

            @memcpy(&announce.public.dh, bytes[index .. index + announce.public.dh.len]);
            index += announce.public.dh.len;
            @memcpy(&announce.public.signature.bytes, bytes[index .. index + announce.public.signature.bytes.len]);
            announce.public.signature = try crypto.Ed25519.PublicKey.fromBytes(announce.public.signature.bytes);
            index += announce.public.signature.bytes.len;
            @memcpy(&announce.noise, bytes[index .. index + announce.noise.len]);
            index += announce.noise.len;
            announce.timestamp = std.mem.bytesToValue(u40, bytes[index .. index + @sizeOf(Announce.Timestamp)]);
            index += @sizeOf(Announce.Timestamp);
            var signature_bytes: [Signature.encoded_length]u8 = undefined;
            @memcpy(&signature_bytes, bytes[index .. index + Signature.encoded_length]);
            announce.signature = Signature.fromBytes(signature_bytes);
            index += Signature.encoded_length;

            var application_data = Bytes.init(self.ally);
            try application_data.appendSlice(bytes[index..]);
            announce.application_data = application_data;

            break :blk announce;
        } },
        else => .{ .raw = blk: {
            var raw = Bytes.init(self.ally);
            errdefer {
                raw.deinit();
            }
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

// TODO: Add ratchet.
pub fn make_announce(self: *Self, endpoint: *const Endpoint, application_data: ?[]const u8) Error!Packet {
    var announce: packet.Payload.Announce = undefined;

    announce.public = endpoint.identity.public;
    announce.name_hash = endpoint.name_hash.name().*;
    self.rng.bytes(&announce.noise);
    announce.timestamp = @truncate(std.mem.nativeToBig(u64, self.clock.monotonicMicros()));
    announce.application_data = Bytes.init(self.ally);

    if (application_data) |data| {
        try announce.application_data.appendSlice(data);
    }

    announce.signature = blk: {
        var signer = try endpoint.identity.signer(&self.rng);
        signer.update(endpoint.hash.short());
        signer.update(announce.public.dh[0..]);
        signer.update(announce.public.signature.bytes[0..]);
        signer.update(announce.name_hash[0..]);
        signer.update(announce.noise[0..]);
        signer.update(&std.mem.toBytes(announce.timestamp));
        signer.update(announce.application_data.items);
        break :blk signer.finalize();
    };

    var builder = Builder.init(self.ally);

    if (self.config.access_code) |interface_access_code| {
        _ = try builder.set_interface_access_code(interface_access_code);
    }

    return try builder
        .set_endpoint(endpoint.hash.short().*)
        .set_payload(.{ .announce = announce })
        .build();
}
