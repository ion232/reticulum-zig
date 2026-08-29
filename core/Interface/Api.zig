pub const Api = struct {
    ptr: *anyopaque,
    announceFn: *const fn (ptr: *anyopaque, hash: Hash, app_data: ?data.Bytes) Error!void,
    plainFn: *const fn (ptr: *anyopaque, name: Name, payload: Payload) Error!void,
    deliverRawPacketFn: *const fn (ptr: *anyopaque, raw_bytes: []const u8) Error!void,
    deliverPacketFn: *const fn (ptr: *anyopaque, packet: Packet) Error!void,
    deliverEventFn: *const fn (ptr: *anyopaque, event: Event.In) Error!void,
    collectEventFn: *const fn (ptr: *anyopaque) ?Event.Out,

    pub fn announce(self: *@This(), hash: Hash, app_data: ?data.Bytes) Error!void {
        return self.announceFn(self.ptr, hash, app_data);
    }

    pub fn plain(self: *@This(), name: Name, payload: Payload) Error!void {
        return self.plainFn(self.ptr, name, payload);
    }

    pub fn deliverRawPacket(self: *@This(), raw_bytes: []const u8) Error!void {
        return self.deliverRawPacketFn(self.ptr, raw_bytes);
    }

    pub fn deliverPacket(self: *@This(), packet: Packet) Error!void {
        return self.deliverPacketFn(self.ptr, packet);
    }

    pub fn deliverEvent(self: *@This(), event: Event.In) Error!void {
        return self.deliverEventFn(self.ptr, event);
    }

    pub fn collectEvent(self: *@This()) ?Event.Out {
        return self.collectEventFn(self.ptr);
    }
};
