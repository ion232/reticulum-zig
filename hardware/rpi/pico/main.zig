// Adapted from the microzig usb_cdc example.

const std = @import("std");
const rt = @import("reticulum");
const microzig = @import("microzig");
const rp2 = microzig.hal;

const Clock = @import("Clock.zig");
const Led = @import("Led.zig");
const Uart = @import("Uart.zig");
const UsbSerial = @import("serial.zig").Usb;

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.log.err("panic: {s}", .{message});
    @breakpoint();
    while (true) {}
}

pub const microzig_options = .{
    .log_level = .debug,
    .logFn = rp2.uart.logFn,
};

var heap: [16_000]u8 = .{0} ** 16_000;

pub fn main() !void {
    var led = Led.init(25);
    var uart = Uart.init();
    var serial = UsbSerial.init();

    led.setup();
    uart.setup();
    serial.setup();

    var fba = std.heap.FixedBufferAllocator.init(&heap);
    var pico_clock: Clock = .{};
    var ascon = rp2.rand.Ascon.init();

    const ally = fba.allocator();
    var clock = pico_clock.clock();
    var rng = ascon.random();

    const announce = try make_announce(ally, clock, &rng);
    const half_a_second = 500000;
    var timestamp: u64 = clock.monotonicMicros();

    while (true) {
        serial.task();

        const now = clock.monotonicMicros();
        if (now - timestamp > half_a_second) {
            timestamp = now;
            led.toggle();

            serial.writePacket(&announce);
        }

        const message = serial.read();
        if (message.len > 0) {
            const hash = rt.crypto.Hash.hash_data(message);
            serial.writeFmt("Your message: {s} => hash {s}\n", .{ message, hash.hex() });
        }
    }
}

fn make_announce(ally: std.mem.Allocator, clock: rt.System.Clock, rng: *rt.System.Rng) !rt.Packet {
    const identity = try rt.crypto.Identity.random(rng);

    var builder = rt.endpoint.Builder.init(ally);
    _ = try builder
        .set_identity(identity)
        .set_direction(.in)
        .set_method(.single)
        .set_application_name("reticulum-pico");
    _ = try builder.append_aspect("test");
    const endpoint = try builder.build();

    var packet_factory = rt.packet.Factory.init(ally, clock, rng.*, .{});
    return try packet_factory.make_announce(&endpoint, "some application data");
}
