const std = @import("std");
const core = @import("core");
const hdlc = @import("../framing.zig").hdlc;
const log = std.log.scoped(.tcp_driver);

const Allocator = std.mem.Allocator;

const Self = @This();

const mtu = 262_144;

ally: Allocator,
running: bool,
node: *core.Node,
host: []const u8,
port: u16,
stream_reader: ?std.net.Stream.Reader,
stream_writer: ?std.net.Stream.Writer,
hdlc_reader: ?hdlc.Reader,
hdlc_writer: ?hdlc.Writer,

pub fn init(node: *core.Node, host: []const u8, port: u16, ally: Allocator) !Self {
    return .{
        .ally = ally,
        .running = false,
        .node = node,
        .host = try ally.dupe(u8, host),
        .port = port,
        .stream_reader = null,
        .stream_writer = null,
        .hdlc_reader = null,
        .hdlc_writer = null,
    };
}

pub fn deinit(self: *Self) void {
    self.running = false;
    self.ally.destroy(&self.host);

    if (self.hdlc_reader) |r| {
        self.ally.free(r.reader.buffer);
    }

    if (self.hdlc_writer) |w| {
        self.ally.free(w.writer.buffer);
    }
}

pub fn run(self: *Self) !void {
    try self.connect();
    self.running = true;

    var hdlc_reader = self.hdlc_reader orelse return error.NoReader;
    // TODO: Replace with 2 * packet mtu.
    var frame: [1024]u8 = @splat(0);

    while (self.running) {
        const n = hdlc_reader.readFrame(&frame) catch |err| {
            switch (err) {
                error.EndOfStream => continue,
                else => return err,
            }
        };

        if (n == 0) continue;

        try self.handleFrame(frame[0..n]);
    }
}

fn connect(self: *Self) !void {
    const address_list = try std.net.getAddressList(self.ally, self.host, self.port);
    defer address_list.deinit();

    if (address_list.addrs.len == 0) return error.FailedHostLookup;

    const address = address_list.addrs[0];
    var stream = try std.net.tcpConnectToAddress(address);

    self.stream_reader = stream.reader(try self.ally.alloc(u8, mtu));
    self.stream_writer = stream.writer(try self.ally.alloc(u8, mtu));
    self.hdlc_reader = hdlc.Reader.init(self.stream_reader.?.interface());
    self.hdlc_writer = hdlc.Writer.init(&self.stream_writer.?.interface);

    log.info("connected to {s}:{d} at {f}", .{ self.host, self.port, address });
}

pub fn write(self: *Self, data: []const u8) !void {
    const writer = self.writer orelse return error.NotConnected;
    const n = try writer.writeFrame(data);
    log.debug("sent {d} bytes", .{n});
}

fn handleFrame(self: *Self, data: []const u8) !void {
    log.debug("handling frame ({d} bytes)", .{data.len});
    // log.debug("raw bytes: {f}", .{std.fmt.hex(data)});

    var factory = core.packet.Factory.init(self.ally, std.crypto.random, .{});
    var packet = factory.fromBytes(data) catch |err| {
        log.err("failed to parse packet: {any}", .{err});
        return;
    };

    // This is just here for testing for now.
    var event = core.Node.Event.Out{ .packet = packet };
    defer event.deinit();

    log.info("{f}", .{event});

    if (packet.header.purpose == .announce) {
        packet.validate() catch |err| {
            log.err("announce validation failed: {any}", .{err});
            return;
        };
        log.info("announce validation succeeded", .{});
    }
}
