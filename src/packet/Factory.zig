const std = @import("std");
const crypto = @import("../crypto.zig");
const packet = @import("../packet.zig");

const Allocator = std.mem.Allocator;
const Rng = @import("../System.zig").Rng;
const Clock = @import("../System.zig").Clock;
const InterfaceConfig = @import("../interface.zig").Config;
const Bytes = std.ArrayList(u8);
const Endpoint = @import("../endpoint.zig").Managed;
const Builder = @import("Builder.zig");
const Packet = @import("Managed.zig");

pub const Error = error{
    InvalidBytesLength,
    InvalidAuthentication,
} || crypto.Identity.Error;
const Self = @This();

ally: Allocator,
clock: Clock,
rng: Rng,
interface: InterfaceConfig,

pub fn init(ally: Allocator, clock: Clock, rng: Rng, interface: InterfaceConfig) Self {
    return Self{
        .ally = ally,
        .clock = clock,
        .rng = rng,
        .interface = interface,
    };
}

pub fn from_bytes(self: *Self, bytes: []const u8) Error!Packet {
    // TODO: This definitely needs tidying up.
    var index = 0;
    const header_size = @sizeOf(packet.Header);

    if (bytes.len < index + header_size) {
        return Error.InvalidBytesLength;
    }

    const header: packet.Header = @bitCast(bytes[index .. index + header_size]);
    index += header_size;

    const both_auth = self.interface.access_code != null and header.interface == .authenticated;
    const both_not_auth = self.interface.access_code == null and header.interface == .open;
    const non_matching_auth = !both_auth or !both_not_auth;

    if (non_matching_auth) {
        return Error.InvalidAuthentication;
    }

    const interface_access_code = Bytes.init(self.ally);
    errdefer {
        interface_access_code.deinit();
    }

    if (self.interface.access_code) |access_code| {
        if (bytes.len < index + access_code.len) {
            return Error.InvalidBytesLength;
        }

        // I need to decrypt the packet here.

        try interface_access_code.appendSlice(bytes[index .. index + access_code.len]);
        index += access_code.len;
    }

    const endpoints_size = switch (header.format) {
        .normal => @sizeOf(Packet.Endpoints.Normal),
        .transport => @sizeOf(Packet.Endpoints.Transport),
    };

    if (bytes.len < index + endpoints_size) {
        return Error.InvalidBytesLength;
    }

    const endpoints = switch (header.format) {
        .normal => blk: {
            const endpoint = Bytes.init(self.ally);
            errdefer {
                endpoint.deinit();
            }
            try endpoint.appendSlice(bytes[index .. index + endpoints_size]);
            index += endpoints_size;

            break :blk Packet.Endpoints{ .normal = .{
                .endpoint = endpoint,
            } };
        },
        .transport => blk: {
            // TODO: Make this cleaner.
            const transport_id = Bytes.init(self.ally);
            errdefer {
                transport_id.deinit();
            }
            try transport_id.appendSlice(bytes[index .. index + @sizeOf(Packet.Endpoints.Normal)]);
            index += @sizeOf(Packet.Endpoints.Normal);

            const endpoint = Bytes.init(self.ally);
            errdefer {
                endpoint.deinit();
            }
            try endpoint.appendSlice(bytes[index .. index + @sizeOf(Packet.Endpoints.Normal)]);
            index += @sizeOf(Packet.Endpoints.Normal);

            break :blk Packet.Endpoints{ .transport = .{
                .transport_id = transport_id,
                .endpoint = endpoint,
            } };
        },
    };

    const context_size = @sizeOf(packet.Context);

    if (bytes.len < index + context_size) {
        return Error.InvalidBytesLength;
    }

    const context = bytes[index .. index + context_size];
    index += context_size;

    const payload: packet.Payload = switch (header.purpose) {
        .announce => .{ .announce = blk: {
            const Announce = packet.Payload.Announce;
            const Signature = crypto.Ed25519.Signature;
            var announce: Announce = undefined;

            if (bytes.len < index + Announce.minimum_size) {
                return Error.InvalidBytesLength;
            }

            announce.public.dh = bytes[index .. index + announce.public.dh.len];
            index += announce.public.dh.len;
            announce.public.signature = try crypto.Ed25519.PublicKey.fromBytes(bytes[index .. index + announce.public.signature.bytes.len]);
            index += announce.public.signature.bytes.len;
            announce.noise = bytes[index .. index + announce.noise.len];
            index += announce.noise.len;
            announce.timestamp = std.mem.bytesToValue(u40, bytes[index .. index + @sizeOf(Announce.Timestamp)]);
            index += @sizeOf(Announce.Timestamp);
            announce.signature = Signature.fromBytes(bytes[index .. index + Signature.encoded_length]);
            index += Signature.encoded_length;

            var application_data = Bytes.init(self.ally);
            application_data.appendSlice(bytes[index..]);
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

// TODO: Make this more efficient.
// TODO: Add ratchet.
pub fn make_announce(self: *Self, endpoint: *const Endpoint, application_data: ?[]const u8) Error!Packet {
    var announce: packet.Payload.Announce = undefined;

    announce.public = endpoint.identity.public;
    announce.name_hash = endpoint.name_hash.name().*;
    self.rng.bytes(&announce.noise);
    announce.timestamp = @truncate(std.mem.nativeToBig(u64, self.clock.monotonicNanos()));
    announce.application_data = Bytes.init(self.ally);

    if (application_data) |data| {
        try announce.application_data.appendSlice(data);
    }

    announce.signature = blk: {
        var signer = try endpoint.identity.signer();
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

    if (self.interface.access_code) |interface_access_code| {
        _ = try builder.set_interface_access_code(interface_access_code);
    }

    return builder
        .set_endpoint(endpoint.hash.short().*)
        .set_payload(.{ .announce = announce })
        .build();
}
