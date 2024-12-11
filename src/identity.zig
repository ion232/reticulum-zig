const Identity = struct {
    short_hash: ShortHash,
};

const ShortHash = struct {
    const len: usize = 16;

    bytes: [len]u8,
    hex_string: [len:0]u8,
};

const Direction = enum {
    in,
    out,
};
