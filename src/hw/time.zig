const time = @import("std").time;

pub fn now_us() u64 {
    return @max(0, time.microTimestamp());
}
