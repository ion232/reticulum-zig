const std = @import("std");
const crypto = @import("../crypto.zig");
const packet = @import("../packet.zig");

pub const Endpoints = packet.Endpoints;

const Allocator = std.mem.Allocator;
const Bytes = std.ArrayList(u8);
const Managed = @import("Managed.zig");
const Hash = crypto.Hash;
const Header = packet.Header;
const Context = packet.Context;
const Payload = packet.Payload;
const Endpoint = @import("../endpoint.zig").Managed;

const Self = @This();
const Fields = std.bit_set.IntegerBitSet(1);

pub const Error = error{Incomplete};

ally: Allocator,
fields: Fields,
header: Header,
interface_access_code: Bytes,
endpoints: Endpoints,
context: Context,
payload: Payload,

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .fields = Fields.initEmpty(),
        .header = .{},
        .interface_access_code = Bytes.init(ally),
        .endpoints = undefined,
        .context = .none,
        .payload = .none,
    };
}

pub fn set_header(self: *Self, header: Header) *Self {
    self.header = header;
    return self;
}

pub fn set_interface_access_code(self: *Self, interface_access_code: []const u8) !*Self {
    try self.interface_access_code.appendSlice(interface_access_code);
    if (interface_access_code.len > 0) {
        self.header.interface = .authenticated;
    }
    return self;
}

pub fn set_endpoint(self: *Self, endpoint_hash: Hash.Short) *Self {
    self.fields.set(0);
    self.endpoints = .{
        .normal = .{ .endpoint = endpoint_hash },
    };
    self.header.format = .normal;
    return self;
}

pub fn set_transport(self: *Self, endpoint_hash: Hash.Short, transport_id: Hash.Short) *Self {
    self.fields.set(0);
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

pub fn set_method(self: *Self, method: Header.Flag.Method) *Self {
    self.header.method = method;
    return self;
}

pub fn set_purpose(self: *Self, purpose: Header.Flag.Purpose) *Self {
    self.header.purpose = purpose;
    return self;
}

pub fn set_context(self: *Self, context: Context) *Self {
    self.context = context;
    self.header.context = .some;
    return self;
}

pub fn set_payload(self: *Self, payload: Payload) *Self {
    self.header.purpose = switch (payload) {
        .announce => .announce,
        else => self.header.purpose,
    };
    self.payload = payload;
    return self;
}

pub fn append_payload(self: *Self, payload: []const u8) !*Self {
    try self.payload.appendSlice(payload);
    return self;
}

pub fn build(self: *Self) !Managed {
    if (self.fields.count() == self.fields.capacity()) {
        return Managed{
            .ally = self.ally,
            .header = self.header,
            .interface_access_code = self.interface_access_code,
            .endpoints = self.endpoints,
            .context = self.context,
            .payload = self.payload,
        };
    }

    return Error.Incomplete;
}
