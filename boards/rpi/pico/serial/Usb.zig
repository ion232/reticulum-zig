const std = @import("std");
const core = @import("reticulum");
const microzig = @import("microzig");
const rp2 = microzig.hal;

const Self = @This();

const UsbDevice = rp2.usb.Usb(.{});
const UsbClassDriver = rp2.usb.types.UsbClassDriver;
const CdcDriver = rp2.usb.cdc.CdcClassDriver(UsbDevice);
const DeviceConfiguration = rp2.usb.DeviceConfiguration;
const Config = struct {
    const endpoint_in_1 = rp2.usb.Endpoint.to_address(1, .In);
    const endpoint_in_2 = rp2.usb.Endpoint.to_address(2, .In);
    const endpoint_out_2 = rp2.usb.Endpoint.to_address(2, .Out);
    const config_descriptor = rp2.usb.templates.config_descriptor(1, 2, 0, descriptors_length, 0xc0, 100);
    const cdc_descriptor = rp2.usb.templates.cdc_descriptor(0, 4, endpoint_in_1, 8, endpoint_out_2, endpoint_in_2, 64);
    const descriptors = config_descriptor ++ cdc_descriptor;
    const descriptors_length = rp2.usb.templates.config_descriptor_len + rp2.usb.templates.cdc_descriptor_len;
};
var cdc_driver: CdcDriver = .{};
var drivers = [_]UsbClassDriver{cdc_driver.driver()};
var device_configuration = DeviceConfiguration{
    .device_descriptor = &.{
        .descriptor_type = rp2.usb.DescType.Device,
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
    .config_descriptor = &Config.descriptors,
    .lang_descriptor = "\x04\x03\x09\x04", // length || string descriptor (0x03) || Engl (0x0409)
    .descriptor_strings = &.{
        &rp2.usb.utils.utf8ToUtf16Le("Raspberry Pi"),
        &rp2.usb.utils.utf8ToUtf16Le("Pico Test Device"),
        &rp2.usb.utils.utf8ToUtf16Le("someserial"),
        &rp2.usb.utils.utf8ToUtf16Le("Board CDC"),
    },
    .drivers = &drivers,
};

pub const buffer_size = 1024;

tx_buffer: [buffer_size]u8,
rx_buffer: [buffer_size]u8,

pub fn init() Self {
    return Self{
        .tx_buffer = .{0} ** buffer_size,
        .rx_buffer = .{0} ** buffer_size,
    };
}

pub fn setup(self: *Self) void {
    _ = self;
    UsbDevice.init_clk();
    UsbDevice.init_device(&device_configuration) catch unreachable;
}

pub fn task(self: *Self) void {
    _ = self;
    const no_debug_over_uart = false;
    UsbDevice.task(no_debug_over_uart) catch unreachable;
}

pub fn writePacket(self: *Self, packet: *const core.packet.Packet) void {
    var write_buff: []const u8 = packet.write(&self.tx_buffer);
    while (write_buff.len > 0) {
        write_buff = cdc_driver.write(write_buff);
    }
}

pub fn writeFmt(self: *Self, comptime fmt: []const u8, args: anytype) void {
    const text = std.fmt.bufPrint(&self.tx_buffer, fmt, args) catch &.{};

    var write_buff = text;
    while (write_buff.len > 0) {
        write_buff = cdc_driver.write(write_buff);
    }
}

pub fn read(self: *Self) []const u8 {
    var total_read: usize = 0;
    var read_buff: []u8 = self.rx_buffer[0..];

    while (true) {
        const len = cdc_driver.read(read_buff);
        read_buff = read_buff[len..];
        total_read += len;
        if (len == 0) break;
    }

    return self.rx_buffer[0..total_read];
}
