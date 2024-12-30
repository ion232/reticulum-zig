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
};
const Self = @This();

ally: Allocator,
clock: Clock,
rng: Rng,
interface: InterfaceConfig,

pub fn init(ally: Allocator, clock: Clock, rng: Rng, interface: *const InterfaceConfig) Self {
    return Self{
        .ally = ally,
        .clock = clock,
        .rng = rng,
        .interface = interface,
    };
}

pub fn from_bytes(self: *Self, bytes: []const u8) !Packet {
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

    const payload = Bytes.init(self.ally);
    errdefer {
        payload.deinit();
    }
    try payload.appendSlice(bytes[index..]);

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
pub fn announce(self: *Self, endpoint: *const Endpoint, application_data: ?[]const u8) !Packet {
    const now: u64 = std.mem.nativeToBig(self.clock.monotonicNanos());
    // TODO: Move this somewhere else.
    const noise_length = 5;
    const noise: [noise_length]u8 = undefined;
    self.rng.bytes(&noise);
    // TODO: Derive this properly.
    const time_bytes = std.mem.asBytes(&now)[3..8];

    const signature = blk: {
        const signing_data = Bytes.init(self.ally);

        defer {
            signing_data.deinit();
        }

        try signing_data.appendSlice(endpoint.hash.short());
        try signing_data.appendSlice(endpoint.identity.public.dh[0..]);
        try signing_data.appendSlice(endpoint.identity.public.signature[0..]);
        try signing_data.appendSlice(endpoint.name_hash);
        try signing_data.appendSlice(noise);
        try signing_data.appendSlice(time_bytes);
        // TODO: Add ratchet.
        try signing_data.appendSlice(application_data[0..]);

        break :blk try endpoint.identity.sign(signing_data.items[0..]);
    };

    const interface_access_code = Bytes.init(self.ally);
    const interface_flag = .open;

    if (self.interface.access_code) |c| {
        interface_access_code.appendSlice(c);
        interface_flag = .authenticated;
    }

    const header = packet.Header{
        .context = .off,
        .format = .normal,
        .hops = 0,
        .interface = interface_flag,
        .method = .single,
        .propagation = .broadcast,
        .purpose = .announce,
    };

    return try Builder.init(self.ally)
        .set_context(0)
        .set_endpoints(Packet.Endpoints{ .normal = endpoint.hash.short() })
        .set_header(header)
        .set_interface_access_code(interface_access_code)
        .append_payload(endpoint.identity.public.dh[0..])
        .append_payload(endpoint.identity.public.signature[0..])
        .append_payload(endpoint.name_hash)
        .append_payload(noise)
        .append_payload(time_bytes)
    // TODO: Add ratchet.
        .append_payload(signature.toBytes()[0..])
        .append_payload(application_data[0..])
        .build();
}
