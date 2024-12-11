const Destination = struct {};

const Direction = enum {
    in,
    out,
};

const Type = enum {
    plain,
    single,
    group,
    link,
};

// Make an announcment packet for a destination.
