const time = @import("std").time;

// Abstract away via some sort of interface.
// Needs to use Timer instead.
pub fn now_us() u64 {
    return @max(0, time.microTimestamp());
}
