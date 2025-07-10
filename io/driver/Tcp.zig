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
stream: ?std.net.Stream,
reader: ?hdlc.Reader(std.net.Stream.Reader, mtu),
writer: ?hdlc.Writer(std.net.Stream.Writer),

pub fn init(node: *core.Node, host: []const u8, port: u16, ally: Allocator) !Self {
    return .{
        .ally = ally,
        .running = false,
        .node = node,
        .host = try ally.dupe(u8, host),
        .port = port,
        .stream = null,
        .reader = null,
        .writer = null,
    };
}

pub fn deinit(self: *Self) void {
    self.running = false;
    self.ally.destroy(&self.host);

    if (self.stream) |stream| {
        stream.close();
        self.stream = null;
    }

    if (self.reader) |*reader| {
        reader.deinit();
    }
}

pub fn run(self: *Self) !void {
    try self.connect();
    self.running = true;

    var reader = self.reader orelse return error.NoReader;
    var frames: [1024][]const u8 = undefined;

    while (self.running) {
        const n = reader.readFrames(&frames) catch |err| {
            if (err == error.EndOfStream) continue else return err;
        };

        for (frames[0..n]) |frame| {
            try self.handleFrame(frame);
        }
    }
}

fn connect(self: *Self) !void {
    const address_list = try std.net.getAddressList(self.ally, self.host, self.port);
    defer address_list.deinit();

    if (address_list.addrs.len == 0) {
        return error.FailedHostLookup;
    }

    const address = address_list.addrs[0];
    self.stream = try std.net.tcpConnectToAddress(address);
    self.reader = try hdlc.Reader(std.net.Stream.Reader, mtu).init(
        self.stream.?.reader(),
        self.ally,
    );
    self.writer = hdlc.Writer(std.net.Stream.Writer).init(
        self.stream.?.writer(),
    );

    log.info("connected to {s}:{} at {}", .{ self.host, self.port, address });
}

pub fn write(self: *Self, data: []const u8) !void {
    const writer = self.writer orelse return error.NotConnected;
    const n = try writer.writeFrame(data);
    log.debug("sent {} bytes", .{n});
}

fn handleFrame(self: *Self, data: []const u8) !void {
    log.debug("handling frame ({} bytes)", .{data.len});
    log.debug("raw bytes: {}", .{std.fmt.fmtSliceHexLower(data)});

    var factory = core.packet.Factory.init(self.ally, std.crypto.random, .{});
    var packet = factory.fromBytes(data) catch |err| {
        log.err("failed to parse packet: {}", .{err});
        return;
    };

    // This is just here for testing for now.
    var event = core.Node.Event.Out{ .packet = packet };
    defer event.deinit();

    log.info("{}", .{event});

    if (packet.header.purpose == .announce) {
        packet.validate() catch |err| {
            log.err("announce validation failed: {}", .{err});
            return;
        };
        log.info("announce validation succeeded", .{});
    }
}
