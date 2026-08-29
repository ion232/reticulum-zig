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

const Self = @This();

const AnnounceQueue = std.PriorityQueue(
    Announce,
    void,
    compareHops,
);

const Announce = struct {
    announce: Packet,
    timestamp: u64,
};

pub const max_queued_announces = if (builtin.target.os.tag == .freestanding) 32 else 16384;

announce_queue: AnnounceQueue,
announce_release_time: u64,
announce_capacity: u8,

pub fn process() void {
    // Do retransmits, etc.
}

fn compareHops(ctx: void, a: Announce, b: Announce) std.math.Order {
    _ = ctx;
    return std.math.order(a.announce.header.hops, b.announce.header.hops);
}
