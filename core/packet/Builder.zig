const std = @import("std");
const crypto = @import("../crypto.zig");
const data = @import("../data.zig");
const packet = @import("../packet.zig");

pub const Endpoints = packet.Endpoints;

const Allocator = std.mem.Allocator;
const Managed = @import("Managed.zig");
const Hash = crypto.Hash;
const Header = packet.Header;
const Context = packet.Context;
const Payload = packet.Payload;
const Endpoint = @import("../endpoint.zig").Managed;

const Self = @This();

pub const Error = error{Incomplete};

ally: Allocator,
header: Header,
interface_access_code: data.Bytes,
endpoints: ?Endpoints,
context: Context,
payload: Payload,

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .header = .{},
        .interface_access_code = data.Bytes.init(ally),
        .endpoints = null,
        .context = .none,
        .payload = .none,
    };
}

pub fn setHeader(self: *Self, header: Header) *Self {
    self.header = header;
    return self;
}

pub fn setInterfaceAccessCode(self: *Self, interface_access_code: []const u8) !*Self {
    try self.interface_access_code.appendSlice(interface_access_code);

    if (interface_access_code.len > 0) {
        self.header.interface = .authenticated;
    }

    return self;
}

pub fn setEndpoint(self: *Self, endpoint_hash: Hash.Short) *Self {
    self.endpoints = .{
        .normal = .{
            .endpoint = endpoint_hash,
        },
    };
    self.header.format = .normal;
    return self;
}

pub fn setTransport(self: *Self, endpoint_hash: Hash.Short, transport_id: Hash.Short) *Self {
    self.endpoints = .{
        .transport = .{
            .endpoint = endpoint_hash,
            .transport_id = transport_id,
        },
    };
    self.header.format = .transport;
    self.header.propagation = .transport;
    return self;
}

pub fn setMethod(self: *Self, method: Header.Flag.Method) *Self {
    self.header.method = method;
    return self;
}

pub fn setPurpose(self: *Self, purpose: Header.Flag.Purpose) *Self {
    self.header.purpose = purpose;
    return self;
}

pub fn setContext(self: *Self, context: Context) *Self {
    self.context = context;
    self.header.context = .some;
    return self;
}

pub fn setPayload(self: *Self, payload: Payload) *Self {
    self.header.purpose = switch (payload) {
        .announce => .announce,
        else => self.header.purpose,
    };
    self.payload = payload;
    return self;
}

pub fn appendPayload(self: *Self, payload: []const u8) !*Self {
    try self.payload.appendSlice(payload);
    return self;
}

pub fn build(self: *Self) !Managed {
    const endpoints = self.endpoints orelse return Error.Incomplete;

    return Managed{
        .ally = self.ally,
        .header = self.header,
        .interface_access_code = self.interface_access_code,
        .endpoints = endpoints,
        .context = self.context,
        .payload = self.payload,
    };
}
