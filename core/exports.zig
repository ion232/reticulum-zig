//! This file is not part of the core module and therefore can contain non-freestanding code.
//! Be aware that this file will be imported into the build executable in order to generate the header file.

const builtin = @import("builtin");
const std = @import("std");
const lib = @import("lib.zig");

const is_wasm = (builtin.cpu.arch == .wasm32 or builtin.cpu.arch == .wasm64);

const Gpa = if (is_wasm) void else std.heap.GeneralPurposeAllocator(.{});
const Allocator = std.mem.Allocator;

const Self = @This();

var gpa: ?Gpa = null;
var allocator: ?Allocator = null;
var clock: lib.System.SimpleClock = undefined;
var rng: lib.System.SimpleRng = undefined;
var system: lib.System = undefined;

// Exported structs and functions.

pub const Error = enum(c_int) {
    none = 0,
    already_initialized = 1,
    missing_allocator = 2,
    out_of_memory = 3,
    leaked_memory = 4,
    unknown = 255,
};

pub fn libInit(
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

    // std.debug.print("Hello from a wasm module!\n", .{});

    return .none;
}

pub fn libDeinit() callconv(.c) Error {
    allocator = null;

    if (is_wasm) {
        return .none;
    }

    if (gpa) |*g| {
        if (g.deinit() == .leak) return .leaked_memory;
    }

    return .none;
}

pub fn makeNode(node_ptr: **anyopaque) callconv(.c) Error {
    const ally = allocator orelse return .missing_allocator;

    const node = ally.create(lib.Node) catch |e| return convertError(Allocator.Error, e);
    errdefer ally.destroy(node);

    node_ptr.* = node;
    node.* = lib.Node.init(
        ally,
        &system,
        null,
        .{},
    ) catch |e| return convertError(lib.Node.Error, e);

    return .none;
}

fn convertError(comptime E: type, e: E) Error {
    if (E == lib.Node.Error) {
        return switch (e) {
            error.OutOfMemory => .out_of_memory,
            else => .unknown,
        };
    }

    return .unknown;
}

// Perform exports.
// This is currently also adding these symbols to the build executable.
// As far as I can tell it won't cause any issues and can probably be changed later.
comptime {
    for (@typeInfo(@This()).@"struct".decls) |declaration| {
        const field = @field(@This(), declaration.name);
        const info = @typeInfo(@TypeOf(field));

        if (info != .@"fn") continue;
        if (std.mem.eql(u8, declaration.name, "generateHeader")) continue;

        const function: *const anyopaque = @ptrCast(&field);
        const export_options = std.builtin.ExportOptions{
            .name = deriveName(declaration.name),
            .linkage = .strong,
        };

        @export(function, export_options);
    }
}

/// This needs to be public for use in the build c step.
pub fn generateHeader() []const u8 {
    comptime var header: []const u8 =
        \\#ifndef RT_CORE_H
        \\#define RT_CORE_H
        \\
        \\#include <stddef.h>
        \\#include <stdint.h>
        \\
        \\
    ;

    inline for (@typeInfo(Self).@"struct".decls) |declaration| {
        const field = @field(Self, declaration.name);
        const info = @typeInfo(@TypeOf(field));

        if (info != .@"fn") continue;
        if (comptime std.mem.eql(u8, declaration.name, "generateHeader")) continue;

        const function = info.@"fn";
        const name = comptime deriveName(declaration.name);
        const return_type = switch (function.return_type.?) {
            Error => "int",
            *anyopaque => "void*",
            c_int => "int",
            else => @typeName(function.return_type.?),
        };

        comptime var forward_declaration: []const u8 = return_type ++ " " ++ name ++ "(";

        inline for (function.params, 0..) |param, i| {
            const param_type = switch (param.type.?) {
                lib.System.SimpleClock.Callback => "int64_t (*monotonic_micros)(void)",
                lib.System.SimpleRng.Callback => "void (*rng_fill)(uint8_t* buf, size_t length)",
                *anyopaque => "void*",
                **anyopaque => "void**",
                c_int => "int",
                else => @typeName(param.type.?),
            };

            forward_declaration = forward_declaration ++ param_type;

            if (i != function.params.len - 1) {
                forward_declaration = forward_declaration ++ ", ";
            }
        }

        forward_declaration = forward_declaration ++ ");\n";

        header = header ++ forward_declaration;
    }

    header = header ++
        \\
        \\#endif
        \\
    ;

    return header;
}

fn deriveName(comptime name: []const u8) []const u8 {
    var c_name: []const u8 = "rt_";

    inline for (name) |char| {
        if (std.ascii.isUpper(char)) {
            c_name = c_name ++ .{ '_', std.ascii.toLower(char) };
        } else {
            c_name = c_name ++ .{char};
        }
    }

    const arch = builtin.target.cpu.arch;

    if (arch == .wasm32 or arch == .wasm64) {
        return name;
    } else {
        return c_name;
    }
}
