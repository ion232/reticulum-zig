//! These exports are currently unstable as the codebase develops.

const bindings = @import("bindings.zig");
const builtin = @import("builtin");
const std = @import("std");
const lib = @import("lib.zig");

const is_wasm = builtin.target.cpu.arch.isWasm();
const Gpa = if (is_wasm) void else std.heap.GeneralPurposeAllocator(.{});
const Allocator = std.mem.Allocator;

const Self = @This();

var gpa: ?Gpa = null;
var allocator: ?Allocator = null;
var clock: lib.System.SimpleClock = undefined;
var rng: lib.System.SimpleRng = undefined;
var system: lib.System = undefined;

/// Error type.
pub const Error = enum(c_int) {
    none = 0,
    already_initialized = 1,
    missing_allocator = 2,
    out_of_memory = 3,
    leaked_memory = 4,
    unknown = 255,
};

/// Sets up the library.
pub fn init(
    monotonicMicros: lib.System.SimpleClock.Callback,
    rngFill: lib.System.SimpleRng.Callback,
) callconv(.c) Error {
    if (allocator != null) return .already_initialized;

    if (is_wasm) {
        allocator = .{
            .ptr = undefined,
            .vtable = &std.heap.WasmAllocator.vtable,
        };
    } else {
        gpa = Gpa{};
        allocator = gpa.?.allocator();
    }

    clock = lib.System.SimpleClock.init(monotonicMicros);
    rng = lib.System.SimpleRng.init(rngFill);
    system = lib.System{
        .clock = clock.clock(),
        .rng = rng.rng(),
    };

    return .none;
}

/// Tears down the library.
pub fn deinit() callconv(.c) Error {
    allocator = null;

    if (is_wasm) {
        return .none;
    }

    if (gpa) |*g| {
        if (g.deinit() == .leak) return .leaked_memory;
    }

    return .none;
}

/// Makes a node.
pub fn makeNode(node_ptr: **anyopaque) callconv(.c) Error {
    const ally = allocator orelse return .missing_allocator;

    const node = ally.create(lib.Node) catch |err| return convertError(Allocator.Error, err);
    errdefer ally.destroy(node);

    node_ptr.* = node;
    node.* = lib.Node.init(
        ally,
        &system,
        null,
        .{},
    ) catch |err| return convertError(lib.Node.Error, err);

    return .none;
}

fn convertError(comptime E: type, err: E) Error {
    if (E == lib.Node.Error) {
        return switch (err) {
            error.OutOfMemory => .out_of_memory,
            else => .unknown,
        };
    }

    return .unknown;
}

comptime {
    for (@typeInfo(@This()).@"struct".decls) |declaration| {
        const field = @field(@This(), declaration.name);
        const info = @typeInfo(@TypeOf(field));

        if (info != .@"fn") continue;

        const function: *const anyopaque = @ptrCast(&field);
        const export_options = std.builtin.ExportOptions{
            .name = bindings.derive(declaration.name),
            .linkage = .strong,
        };

        @export(function, export_options);
    }
}
