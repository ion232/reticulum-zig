const std = @import("std");
const crypto = @import("../crypto.zig");

const Hash = crypto.Hash;
const Packet = @import("../Packet.zig");
const View = @import("View.zig");

const Self = @This();

access_code: []const u8,

pub fn parse(self: *const Self, raw_bytes: []const u8) !View {
    var reader = std.Io.Reader.fixed(raw_bytes);

    const header = try reader.takeInt(Packet.Header, .little);
    const missing_access_code = self.access_code.len == 0 and header.interface == .authenticated;
    const expected_auth_flag = self.access_code.len > 0 and header.interface == .open;

    if (missing_access_code or expected_auth_flag) return error.InvalidAuth;

    const access_code = try reader.take(self.access_code.len);

    const endpoints = switch (header.endpoints) {
        .single => View.Endpoints{
            .single = try reader.takeStructPointer(comptime T: type)
        },
        .transport => View.Endpoints{
            .transport = .{
                .transport = try reader.take(Hash.short_length),
                .target = try reader.take(Hash.short_length),
            },
        },
    };

    const context = try reader.takeEnum(Packet.Context, .big);

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

                var application_data = data.Bytes.empty;
                try application_data.appendSlice(self.ally, bytes[index..]);
                announce.application_data = application_data;

                break :blk announce;
            },
        },
        else => .{ .raw = blk: {
            var raw = data.Bytes.empty;
            errdefer raw.deinit(self.ally);
            try raw.appendSlice(self.ally, bytes[index..]);
            break :blk raw;
        } },
    };
}
