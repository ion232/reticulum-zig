const std = @import("std");
const crypto = @import("../crypto.zig");
const packet = @import("../packet.zig");

const Allocator = std.mem.Allocator;
const Bytes = std.ArrayList(u8);
const Managed = @import("Managed.zig");
const Hash = crypto.Hash;
const Header = packet.Header;
const Context = packet.Context;
const Endpoint = @import("../endpoint.zig").Managed;
const Endpoints = Managed.Endpoints;

const Self = @This();
const Fields = std.bit_set.IntegerBitSet(2);

pub const Error = error{Incomplete};

ally: Allocator,
fields: Fields,
header: Header = undefined,
interface_access_code: Bytes,
endpoints: Endpoints = undefined,
context: Context = 0,
payload: Bytes,

pub fn init(ally: Allocator) Self {
    return Self{
        .ally = ally,
        .fields = Fields.initEmpty(),
        .interface_access_code = Bytes.init(ally),
        .payload = Bytes.init(ally),
    };
}

pub fn set_header(self: *Self, header: Header) *Self {
    self.fields.set(0);
    self.header = header;
    return self;
}

pub fn set_interface_access_code(self: *Self, interface_access_code: []const u8) *Self {
    self.interface_access_code.appendSlice(interface_access_code);
    return self;
}

pub fn set_endpoint(self: *Self, endpoint_hash: Hash.Short) *Self {
    self.fields.set(1);
    self.endpoints = .{
        .normal = .{ .endpoint = endpoint_hash },
    };
    return self;
}

pub fn set_transport(self: *Self, endpoint_hash: Hash.Short, transport_id: Hash.Short) *Self {
    self.fields.set(1);
    self.endpoints = .{
        .transport = .{
            .endpoint = endpoint_hash,
            .transport_id = transport_id,
        },
    };
    return self;
}

pub fn set_context(self: *Self, context: Context) *Self {
    self.context = context;
    return self;
}

pub fn append_payload(self: *Self, payload: []const u8) *Self {
    self.payload.appendSlice(payload);
    return self;
}

pub fn build(self: *Self) Managed {
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
