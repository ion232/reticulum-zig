const std = @import("std");
const microzig = @import("microzig");
const rt = @import("reticulum");

const rp2xxx = microzig.hal;
const flash = rp2xxx.flash;
const rand = rp2xxx.rand;
const time = rp2xxx.time;
const gpio = rp2xxx.gpio;
const clocks = rp2xxx.clocks;
const usb = rp2xxx.usb;
const cpu = rp2xxx.compatibility.cpu;

const led = gpio.num(25);
const uart = rp2xxx.uart.instance.num(0);
const baud_rate = 115200;
const uart_tx_pin = gpio.num(0);
const uart_rx_pin = gpio.num(1);

const usb_dev = rp2xxx.usb.Usb(.{});

const usb_config_len = usb.templates.config_descriptor_len + usb.templates.cdc_descriptor_len;
const usb_config_descriptor =
    usb.templates.config_descriptor(1, 2, 0, usb_config_len, 0xc0, 100) ++
    usb.templates.cdc_descriptor(0, 4, usb.Endpoint.to_address(1, .In), 8, usb.Endpoint.to_address(2, .Out), usb.Endpoint.to_address(2, .In), 64);

var driver_cdc: usb.cdc.CdcClassDriver(usb_dev) = .{};
var drivers = [_]usb.types.UsbClassDriver{driver_cdc.driver()};

// This is our device configuration
pub var DEVICE_CONFIGURATION: usb.DeviceConfiguration = .{
    .device_descriptor = &.{
        .descriptor_type = usb.DescType.Device,
        .bcd_usb = 0x0200,
        .device_class = 0xEF,
        .device_subclass = 2,
        .device_protocol = 1,
        .max_packet_size0 = 64,
        .vendor = 0x2E8A,
        .product = 0x000a,
        .bcd_device = 0x0100,
        .manufacturer_s = 1,
        .product_s = 2,
        .serial_s = 0,
        .num_configurations = 1,
    },
    .config_descriptor = &usb_config_descriptor,
    .lang_descriptor = "\x04\x03\x09\x04", // length || string descriptor (0x03) || Engl (0x0409)
    .descriptor_strings = &.{
        &usb.utils.utf8ToUtf16Le("Raspberry Pi"),
        &usb.utils.utf8ToUtf16Le("Pico Test Device"),
        &usb.utils.utf8ToUtf16Le("someserial"),
        &usb.utils.utf8ToUtf16Le("Board CDC"),
    },
    .drivers = &drivers,
};

pub fn panic(message: []const u8, _: ?*std.builtin.StackTrace, _: ?usize) noreturn {
    std.log.err("panic: {s}", .{message});
    @breakpoint();
    while (true) {}
}

pub const microzig_options = .{
    .log_level = .debug,
    .logFn = rp2xxx.uart.logFn,
};

pub const PicoClock = struct {
    const Self = @This();

    pub fn monotonicNanos(ptr: *anyopaque) u64 {
        _ = ptr;
        // Not actually nanoseconds and realistically doesn't need to be.
        return time.get_time_since_boot().to_us();
    }

    pub fn clock(self: *Self) rt.System.Clock {
        return .{
            .ptr = self,
            .monotonicNanosFn = monotonicNanos,
        };
    }
};

var buffer: [128_000]u8 = undefined;

pub fn main() !void {
    led.set_function(.sio);
    led.set_direction(.out);
    led.put(1);

    var fba = std.heap.FixedBufferAllocator.init(buffer[0..]);
    const ally = fba.allocator();

    var pico_clock: PicoClock = .{};

    var ascon = rand.Ascon.init();
    var rng = ascon.random();
    var rand_buffer: [32]u8 = undefined;
    rng.bytes(&rand_buffer);

    const identity = try rt.crypto.Identity.random(&rng);

    var builder = rt.endpoint.Builder.init(ally);
    _ = try builder
        .set_identity(identity)
        .set_direction(.in)
        .set_method(.single)
        .set_application_name("rpi-pico-reticulum");
    _ = try builder.append_aspect("test");
    const endpoint = try builder.build();

    var packet_factory = rt.packet.Factory.init(ally, pico_clock.clock(), rng, .{});
    var announce = try packet_factory.make_announce(&endpoint, "some application data");
    switch (cpu) {
        .RP2040 => inline for (&.{ uart_tx_pin, uart_rx_pin }) |pin| {
            pin.set_function(.uart);
        },
        .RP2350 => inline for (&.{ uart_tx_pin, uart_rx_pin }) |pin| {
            pin.set_function(.uart_second);
        },
    }

    uart.apply(.{
        .baud_rate = baud_rate,
        .clock_config = rp2xxx.clock_config,
    });

    rp2xxx.uart.init_logger(uart);

    // First we initialize the USB clock
    usb_dev.init_clk();
    // Then initialize the USB device using the configuration defined above
    usb_dev.init_device(&DEVICE_CONFIGURATION) catch unreachable;
    var old: u64 = time.get_time_since_boot().to_us();
    var new: u64 = 0;

    var i: u32 = 0;
    while (true) {
        // You can now poll for USB events
        usb_dev.task(
            false, // debug output over UART [Y/n]
        ) catch unreachable;

        new = time.get_time_since_boot().to_us();
        if (new - old > 500000) {
            old = new;
            led.toggle();
            i += 1;
            std.log.info("cdc test: {}\r\n", .{i});

            // rng.bytes(&rand_buffer);
            // usb_cdc_write("Index: {} buf: {s}\n", .{ i, short_hash });
            usb_cdc_write_packet(&announce);
        }

        // read and print host command if present
        const message = usb_cdc_read();
        if (message.len > 0) {
            const hash = rt.crypto.Hash.hash_data(message);
            usb_cdc_write("Your message: {s} => hash {s}\r\n", .{ message, hash.hex()[0..] });
        }
    }
}

var usb_tx_buff: [1024]u8 = undefined;

pub fn usb_cdc_write_packet(packet: *rt.packet.Packet) void {
    // std.fmt.bytesToHex(text, .lower);
    var write_buff: []const u8 = packet.write(&usb_tx_buff);
    while (write_buff.len > 0) {
        write_buff = driver_cdc.write(write_buff);
    }
}

pub fn usb_cdc_write(comptime fmt: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(&usb_tx_buff, fmt, args) catch &.{};

    var write_buff = text;
    while (write_buff.len > 0) {
        write_buff = driver_cdc.write(write_buff);
    }
}

var usb_rx_buff: [1024]u8 = undefined;

// TODO - right now there are 2 issues with reading data from serial:
// 1. It not always work, so sometime data is not received. This is probably related to how we reset usb buffer flags.
// 2. Even when usb host sends small chunk of data cdc read returns full packet length. This require further investigation.
pub fn usb_cdc_read() []const u8 {
    var total_read: usize = 0;
    var read_buff: []u8 = usb_rx_buff[0..];

    while (true) {
        const len = driver_cdc.read(read_buff);
        read_buff = read_buff[len..];
        total_read += len;
        if (len == 0) break;
    }

    return usb_rx_buff[0..total_read];
}
