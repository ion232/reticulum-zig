const std = @import("std");
const endpoint = @import("../endpoint.zig");
const crypto = @import("../crypto.zig");
const packet = @import("../packet.zig");

const Allocator = std.mem.Allocator;
const Bytes = std.ArrayList(u8);
const Header = packet.Header;
const Context = packet.Context;
const Endpoints = packet.Endpoints;
const Payload = packet.Payload;
const Hash = crypto.Hash;

const Self = @This();

ally: Allocator,
header: Header = undefined,
interface_access_code: Bytes,
endpoints: Endpoints = undefined,
context: Context = undefined,
payload: Payload,

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .interface_access_code = Bytes.init(ally),
        .payload = .none,
    };
}

pub fn validate(self: *Self) !bool {
    switch (self.payload) {
        .announce => |a| {
            const endpoint_hash = a.endpoints.endpoint();
            const verifier = try a.signature.verifier(a.public.signature);
            verifier.update(&endpoint_hash);
            verifier.update(&a.public.dh);
            verifier.update(&a.public.signature);
            verifier.update(&a.name_hash);
            verifier.update(&a.noise);
            verifier.update(&std.mem.asBytes(a.timestamp));
            verifier.update(a.application_data.items);
            try verifier.verify();

            const identity = crypto.Identity.from_public(a.public);
            const expected_hash = Hash.hash_items(.{
                .name_hash = a.name_hash,
                .public_hash = identity.hash.short(),
            });

            const matching_hashes = std.mem.eql(u8, endpoint_hash[0..], expected_hash.short()[0..]);
            return matching_hashes;
        },
        else => return true,
    }
}

// TODO: Make this take a Writer interface.
pub fn write(self: *Self, buffer: []u8) !void {
    if (buffer.len < self.size()) {
        return;
    }

    var i = 0;

    const header_size = @sizeOf(@TypeOf(self.header));
    @memcpy(buffer[i .. i + header_size], &self.header);
    i += header_size;

    if (self.ifac != null) {
        @memcpy(buffer[i .. i + self.ifac.?.len], self.ifac.?);
        i += self.ifac.?.len;
    }

    @memcpy(buffer[i .. i + self.endpoint.len], self.endpoint);
    i += self.endpoint.len;

    if (self.other_endpoint != null) {
        @memcpy(buffer[i .. i + self.other_endpoint.?.len], self.other_endpoint.?);
        i += self.other_endpoint.?.len;
    }

    const context_size = @sizeOf(@TypeOf(self.context));
    @memcpy(buffer[i .. i + context_size], &self.context);
    i += context_size;

    @memcpy(buffer[i .. i + self.payload.len], self.payload);
}

pub fn hash(self: *const Self) Hash {
    const header: u8 = std.mem.bytesAsSlice(u4, self.header)[1];

    return switch (self.endpoints) {
        .normal => |normal| Hash.from_items(.{
            .header = header,
            .endpoint = normal.endpoint,
            .context = self.context,
            .payload = self.payload,
        }),
        .transport => |transport| Hash.from_items(.{
            .header = header,
            .transport_id = transport.transport_id,
            .endpoint = transport.endpoint,
            .context = self.context,
            .payload = self.payload,
        }),
    };
}

pub fn size(self: *Self) usize {
    var total_size: usize = 0;

    total_size += @sizeOf(@TypeOf(self.header));
    total_size += self.interface_access_code.items.len;
    total_size += switch (self.endpoints) {
        .normal => |*n| n.endpoint.items.len,
        .transport => |*t| t.transport_id.items.len + t.endpoint.items.len,
    };
    total_size += @sizeOf(@TypeOf(self.context));
    total_size += self.payload.len;

    return total_size;
}
