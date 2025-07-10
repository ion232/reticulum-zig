const std = @import("std");
const microzig = @import("microzig");
const rp2 = microzig.hal;

const Self = @This();

const uart = rp2.uart.instance.num(0);
const baud_rate = 115200;

tx_pin: rp2.gpio.Pin,
rx_pin: rp2.gpio.Pin,

pub fn init() Self {
    return Self{
        .tx_pin = rp2.gpio.num(0),
        .rx_pin = rp2.gpio.num(1),
    };
}

pub fn setup(self: *Self) void {
    switch (rp2.compatibility.cpu) {
        .RP2040 => inline for (&.{ self.tx_pin, self.rx_pin }) |pin| {
            pin.set_function(.uart);
        },
        .RP2350 => inline for (&.{ self.tx_pin, self.rx_pin }) |pin| {
            pin.set_function(.uart_second);
        },
    }

    uart.apply(.{
        .baud_rate = baud_rate,
        .clock_config = rp2.clock_config,
    });

    rp2.uart.init_logger(uart);
}
