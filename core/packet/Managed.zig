const std = @import("std");
const crypto = @import("../crypto.zig");
const data = @import("../data.zig");
const packet = @import("../packet.zig");

const Allocator = std.mem.Allocator;
const Header = packet.Header;
const Context = packet.Context;
const Endpoints = packet.Endpoints;
const Payload = packet.Payload;
const Hash = crypto.Hash;

const Self = @This();

ally: Allocator,
header: Header,
interface_access_code: data.Bytes,
endpoints: Endpoints,
context: Context,
payload: Payload,

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .header = undefined,
        .interface_access_code = data.Bytes.init(ally),
        .endpoints = undefined,
        .context = undefined,
        .payload = .none,
    };
}

pub fn setTransport(self: *Self, transport_id: *const Hash.Short) !void {
    self.header.format = .transport;
    self.endpoints = Endpoints{
        .transport = Endpoints.Transport{
            .transport_id = transport_id.*,
            .endpoint = self.endpoints.endpoint(),
        },
    };
}

pub fn validate(self: *const Self) !void {
    switch (self.payload) {
        .announce => |a| {
            const endpoint_hash = self.endpoints.endpoint();
            var verifier = try a.signature.verifier(a.public.signature);
            verifier.update(&endpoint_hash);
            verifier.update(&a.public.dh);
            verifier.update(&a.public.signature.bytes);
            verifier.update(&a.name_hash);
            verifier.update(&a.noise);
            verifier.update(std.mem.asBytes(&a.timestamp));
            verifier.update(a.application_data.items);
            try verifier.verify();

            const identity = crypto.Identity.fromPublic(a.public);
            const expected_hash = Hash.of(.{
                .name_hash = a.name_hash,
                .public_hash = identity.hash.short(),
            });

            const matching_hashes = std.mem.eql(u8, endpoint_hash[0..], expected_hash.short()[0..]);
            if (!matching_hashes) {
                return error.MismatchingHashes;
            }
        },
        else => return,
    }
}

// TODO: Make this take a Writer interface.
// TODO: Make sure to encrypt the packet with the interface access code here.
pub fn write(self: *const Self, buffer: []u8) []u8 {
    if (buffer.len < self.size()) {
        return &.{};
    }

    var i: usize = 0;

    const header_size = @sizeOf(@TypeOf(self.header));
    @memcpy(buffer[i .. i + header_size], std.mem.asBytes(&self.header));
    i += header_size;

    if (self.interface_access_code.items.len > 0) {
        @memcpy(buffer[i .. i + self.interface_access_code.items.len], self.interface_access_code.items[0..self.interface_access_code.items.len]);
        i += self.interface_access_code.items.len;
    }

    switch (self.endpoints) {
        .normal => |*n| {
            @memcpy(buffer[i .. i + n.endpoint.len], &n.endpoint);
            i += n.endpoint.len;
        },
        .transport => |*t| {
            @memcpy(buffer[i .. i + t.transport_id.len], &t.transport_id);
            i += t.transport_id.len;
            @memcpy(buffer[i .. i + t.endpoint.len], &t.endpoint);
            i += t.endpoint.len;
        },
    }

    const context_size = @sizeOf(@TypeOf(self.context));
    @memcpy(buffer[i .. i + context_size], std.mem.asBytes(&self.context));
    i += context_size;

    switch (self.payload) {
        .announce => |*a| {
            @memcpy(buffer[i .. i + a.public.dh.len], &a.public.dh);
            i += a.public.dh.len;
            @memcpy(buffer[i .. i + a.name_hash.len], &a.name_hash);
            i += a.name_hash.len;
            @memcpy(buffer[i .. i + a.noise.len], &a.noise);
            i += a.noise.len;
            const timestamp_bytes = std.mem.asBytes(&a.timestamp);
            @memcpy(buffer[i .. i + timestamp_bytes.len], timestamp_bytes);
            i += timestamp_bytes.len;
            @memcpy(buffer[i .. i + crypto.Ed25519.Signature.encoded_length], &a.signature.toBytes());
            i += crypto.Ed25519.Signature.encoded_length;
            @memcpy(buffer[i .. i + a.application_data.items.len], a.application_data.items);
            i += a.application_data.items.len;
        },
        .raw => |*r| {
            @memcpy(buffer[i .. i + r.items.len], r.items);
            i += r.items.len;
        },
        .none => {},
    }

    return buffer[0..i];
}

pub fn hash(self: *const Self) Hash {
    const header = std.mem.asBytes(&self.header);
    const method_and_purpose: u8 = std.mem.bytesAsSlice(u4, header)[1];
    const context = @intFromEnum(self.context);

    var hasher = switch (self.endpoints) {
        .normal => |normal| Hash.incremental(.{
            .method_and_purpose = method_and_purpose,
            .endpoint = normal.endpoint,
            .context = context,
        }),
        .transport => |transport| Hash.incremental(.{
            .method_and_purpose = method_and_purpose,
            .transport_id = transport.transport_id,
            .endpoint = transport.endpoint,
            .context = context,
        }),
    };

    // Could do with a refactor probably.
    switch (self.payload) {
        .announce => |announce| {
            hasher.update(&announce.public.dh);
            hasher.update(&announce.public.signature.bytes);
            hasher.update(&announce.name_hash);
            hasher.update(&announce.noise);
            hasher.update(std.mem.asBytes(&announce.timestamp));
            hasher.update(&announce.signature.r);
            hasher.update(&announce.signature.s);
            hasher.update(announce.application_data.items);
        },
        .raw => |raw| {
            hasher.update(raw.items);
        },
        .none => {},
    }

    return Hash.fromLong(hasher.finalResult());
}

pub fn size(self: *const Self) usize {
    var total_size: usize = 0;

    total_size += @sizeOf(@TypeOf(self.header));
    total_size += self.interface_access_code.items.len;
    total_size += switch (self.endpoints) {
        .normal => |*n| n.endpoint.len,
        .transport => |*t| t.transport_id.len + t.endpoint.len,
    };
    total_size += @sizeOf(@TypeOf(self.context));
    total_size += self.payload.size();

    return total_size;
}

pub fn clone(self: *const Self) !Self {
    return Self{
        .ally = self.ally,
        .context = self.context,
        .endpoints = self.endpoints,
        .header = self.header,
        .interface_access_code = try self.interface_access_code.clone(),
        .payload = try self.payload.clone(),
    };
}

pub fn deinit(self: *Self) void {
    self.interface_access_code.deinit();
    self.payload.deinit();
}
