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

pub fn announce(self: *Self, endpoint: *const Endpoint, application_data: ?[]const u8) !Packet {
    // TODO: Make this more efficient.
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
        break :blk try endpoint.identity.sign(signing_data);
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
