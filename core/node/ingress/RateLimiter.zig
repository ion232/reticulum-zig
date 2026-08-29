const builtin = @import("builtin");
const std = @import("std");
const unit = @import("../unit.zig");

const Allocator = std.mem.Allocator;
const Direction = @import("../endpoint.zig").Direction;
const Event = @import("../node/Event.zig");
const Interface = @import("../Interface.zig");
const Packet = @import("../packet/Managed.zig");
const PacketFactory = @import("../packet/Factory.zig");
const System = @import("../System.zig");

const IncomingAnnounceTimes = std.fifo.LinearFifo(u64, .{ .Static = 6 });
const Burst = struct {
    is_active: bool,
    normal_threshold: u64,
    initial_threshold: u64,
    duration: u64,
    start_time: u64,
    penalty: u64,
};

creation_time: u64,
held_release: u64,
new_time: u64,

incoming_announce_times: IncomingAnnounceTimes,

pub fn process(self: *Self, packet: *const Packet, now: u64) !void {
    if (try self.shouldIngressLimit(entry.interface.id, now) or now <= entry.ingress_control.held_release) continue;

    const lifetime = now - entry.creation_time;
    const control = &entry.ingress_control;
    const frequency = control.announceFrequencyIn(now);
    const threshold = if (lifetime < control.new_time) control.burst_freq_new else control.burst_freq;

    if (frequency >= threshold) continue;

    var announce_entries = entry.held_announces.iterator();
    var min_key: ?[]const u8 = null;
    var min_hops: u8 = 255;

    while (announce_entries.next()) |announce_entry| {
        const hops = announce_entry.value_ptr.header.hops;

        if (hops < min_hops) {
            min_hops = hops;
            min_key = announce_entry.key_ptr.*;
        }
    }

    if (min_key) |k| {
        control.held_release = now + 30_000_000;
        const announce = entry.held_announces.get(k) orelse unreachable;
        try entry.interface.incoming.push(.{
            .packet = announce,
        });
    }
}

pub fn holdAnnounce(self: *Self, id: Interface.Id, announce: Packet) !void {
    const entry = self.entries.getPtr(id) orelse return Error.InterfaceNotFound;

    const max_held_announces = 256;
    if (entry.held_announces.count() > max_held_announces) return;

    const endpoint = announce.endpoints.endpoint();
    const key = try self.ally.dupe(u8, &endpoint);
    try entry.held_announces.put(key, announce);
}

fn announceFrequencyIn(self: *const @This(), now: u64) u64 {
    const count = self.incoming_announce_times.count;

    if (count < 1) return 0;

    var sum = now - self.incoming_announce_times.peekItem(count - 1);

    for (1..count) |i| {
        sum += self.incoming_announce_times.peekItem(i) - self.incoming_announce_times.peekItem(i - 1);
    }

    const average = if (sum != 0) count / sum else 0;

    return average;
}

pub fn shouldIngressLimit(self: *Self, id: Interface.Id, now: u64) !bool {
    const entry = self.entries.getPtr(id) orelse return Error.InterfaceNotFound;
    const lifetime = now - entry.creation_time;
    const control = &entry.ingress_control;

    const frequency = control.announceFrequencyIn(now);
    const threshold = if (lifetime < control.new_time) control.burst_freq_new else control.burst_freq;

    if (control.burst_active) {
        if (frequency < threshold and now > control.burst_activated + control.burst_hold) {
            control.burst_active = false;
            control.held_release = now + control.burst_penalty;
        }

        return true;
    }

    if (frequency > threshold) {
        control.burst_active = true;
        control.burst_activated = now;
        return true;
    }

    return false;
}
