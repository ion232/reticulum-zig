const std = @import("std");
const microzig = @import("microzig");
const rp2 = microzig.hal;

const Self = @This();

pin: rp2.gpio.Pin,

pub fn init(index: u6) Self {
    return Self{
        .pin = rp2.gpio.num(index),
    };
}

pub fn setup(self: *Self) void {
    self.pin.set_function(.sio);
    self.pin.set_direction(.out);
    self.pin.put(1);
}

pub fn toggle(self: *Self) void {
    self.pin.toggle();
}
