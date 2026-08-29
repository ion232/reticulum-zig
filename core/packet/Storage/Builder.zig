const std = @import("std");
const crypto = @import("../../crypto.zig");
const Packet = @import("../../Packet.zig");

const Allocator = std.mem.Allocator;
const Hash = crypto.Hash;
const Identity = crypto.Identity;

const Self = @This();

pub const Error = std.Io.Writer.Error || error{
    InvalidInterfaceAccessCode,
    InvalidEndpoints,
    Incomplete,
};

const State = enum {
    header,
    interface_access_code,
    endpoints,
    context,
    payload_tag,
    public_identity,
    name_hash,
    noise,
    timestamp,
    ratchet,
    signature,
    application_data,
    raw_data,
    done,
    failed,
};

writer: std.Io.Writer,
handle: Packet.Storage.Handle,
header: Packet.Header,
last_error: ?Error,
state: State,

// TODO: Reduce the amount of boilerplate code here.

pub fn init(handle: Packet.Storage.Handle) Self {
    return Self{
        .writer = std.Io.Writer.fixed(handle.ptr),
        .handle = handle,
        .header = @bitCast(0),
        .last_error = null,
        .state = .header,
    };
}

pub fn addHeader(self: *Self, header: Packet.Header) *Self {
    if (self.last_error != null or self.state != .header) return self;

    self.header = header;
    self.writer.writeStruct(header, .big) catch |err| return self.handleError(err);
    self.state = if (header.interface == .authenticated) .interface_access_code else .endpoints;

    return self;
}

pub fn addInterfaceAccessCode(self: *Self, interface_access_code: []const u8) *Self {
    if (self.last_error != null or self.state != .interface_access_code) return self;
    if (interface_access_code.len > 64) return self.handleError(Error.InvalidInterfaceAccessCode);

    self.writer.writeAll(interface_access_code) catch |err| return self.handleError(err);
    self.state = .endpoints;

    return self;
}

pub fn addEndpoints(self: *Self, target: Hash.Short, transport: ?Hash.Short) *Self {
    if (self.last_error != null or self.state != .endpoints) return self;
    if (self.header.endpoints == .single and transport == null) return self.handleError(Error.InvalidEndpoints);
    if (self.header.endpoints == .transport and transport != null) return self.handleError(Error.InvalidEndpoints);

    self.writer.writeAll(target) catch |err| return self.handleError(err);
    if (transport) |t| self.writer.writeAll(t) catch |err| return self.handleError(err);
    self.state = .context;

    return self;
}

pub fn addContext(self: *Self, context: Packet.Context) *Self {
    if (self.last_error != null or self.state != .context) return self;
    if (self.header.context != .some) return self;

    self.writer.writeByte(context) catch |err| return self.handleError(err);
    self.state = .payload_tag;

    return self;
}

pub fn payloadTag(self: *Self, tag: Packet.PayloadTag) *Self {
    self.state = switch (tag) {
        .announce => .public_identity,
        .raw => .raw_data,
        .none => .done,
    };

    return self;
}

pub fn addPublicIdentity(self: *Self, public_identity: Identity.Public) *Self {
    if (self.last_error != null or self.state != .public_identity) return self;

    self.writer.writeAll(public_identity.dh) catch |err| return self.handleError(err);
    self.writer.writeAll(public_identity.signature.bytes) catch |err| return self.handleError(err);
    self.state = .name_hash;

    return self;
}

pub fn addNameHash(self: *Self, name_hash: Hash.Name) *Self {
    if (self.last_error != null or self.state != .name_hash) return self;

    self.writer.writeAll(name_hash) catch |err| return self.handleError(err);
    self.state = .noise;

    return self;
}

pub fn addNoise(self: *Self, noise: Packet.Payload.Announce.Noise) *Self {
    if (self.last_error != null or self.state != .noise) return self;

    self.writer.writeAll(noise) catch |err| return self.handleError(err);
    self.state = .timestamp;

    return self;
}

pub fn addTimestamp(self: *Self, timestamp: Packet.Payload.Announce.Timestamp) *Self {
    if (self.last_error != null or self.state != .timestamp) return self;

    self.writer.writeInt(u40, timestamp, .big) catch |err| return self.handleError(err);
    self.state = if (self.header.context == .some) .ratchet else .signature;

    return self;
}

pub fn addRatchet(self: *Self, ratchet: crypto.Identity.Ratchet) *Self {
    if (self.last_error != null or self.state != .ratchet) return self;

    self.writer.writeAll(ratchet) catch |err| return self.handleError(err);
    self.state = .signature;

    return self;
}

pub fn addSignature(self: *Self, signature: crypto.Ed25519.Signature) *Self {
    if (self.last_error != null or self.state != .signature) return self;

    self.writer.writeAll(signature.toBytes()) catch |err| return self.handleError(err);
    self.state = .application_data;

    return self;
}

pub fn addApplicationData(self: *Self, application_data: []const u8) *Self {
    if (self.last_error != null or self.state != .signature) return self;

    self.writer.writeAll(application_data) catch |err| return self.handleError(err);
    self.state = .done;

    return self;
}

pub fn addRawData(self: *Self, raw_data: []const u8) *Self {
    if (self.last_error != null or self.state != .raw_data) return self;

    self.writer.writeAll(raw_data) catch |err| return self.handleError(err);
    self.state = .done;

    return self;
}

pub fn result(self: *Self) Error![]u8 {
    if (self.last_error) |err| return err;
    if (self.state != .done) return Error.Incomplete;

    return self.writer.buffered();
}

fn handleError(self: *Self, err: Error) *Self {
    self.last_error = err;
    self.state = .failed;
    return self;
}
