const builtin = @import("builtin");
const std = @import("std");

const Allocator = std.mem.Allocator;
const Bytes = std.ArrayList(u8);

const eql = std.mem.eql;

const Language = enum {
    c,
    js,
    rust,
};

pub fn data(language: Language, ally: Allocator) !Bytes {
    var exports = parseExports(@embedFile("exports.zig"), ally);

    return switch (language) {
        .c => try exports.c(),
        .js => try exports.js(),
        .rust => try exports.rust(),
    };
}

fn parseExports(export_data: [:0]const u8, ally: Allocator) Exports {
    const Ast = std.zig.Ast;

    const DocComment = struct {
        fn search(ast: Ast, main_token: u32) []const u8 {
            var t = main_token - 1;

            while (t > 0) : (t -= 1) {
                switch (ast.tokens.items(.tag)[t]) {
                    .doc_comment => return ast.tokenSlice(t)["/// ".len..],
                    .keyword_pub => continue,
                    else => break,
                }
            }

            return "";
        }
    };

    var ast = Ast.parse(ally, export_data, .zig) catch return Exports.init(ally);
    defer ast.deinit(ally);

    const root_declarations = ast.rootDecls();
    const nodes = ast.nodes;
    const tokens = ast.tokens;

    var exports = Exports.init(ally);

    for (root_declarations) |declaration_index| {
        const declaration_tag = nodes.items(.tag)[declaration_index];
        const main_token = nodes.items(.main_token)[declaration_index];

        if (main_token <= 0 or tokens.items(.tag)[main_token - 1] != .keyword_pub) {
            continue;
        }

        if (declaration_tag == .fn_decl) {
            var buffer: [1]std.zig.Ast.Node.Index = undefined;

            const function_prototype = ast.fullFnProto(
                &buffer,
                nodes.items(.data)[declaration_index].lhs,
            ) orelse continue;

            const function = exports.functions.addOne() catch continue;

            function.* = .{
                .doc_comment = DocComment.search(ast, main_token),
                .name = ast.tokenSlice(function_prototype.name_token orelse continue),
                .parameters = std.ArrayList(Function.Parameter).init(ally),
                .return_value = ast.getNodeSource(function_prototype.ast.return_type),
            };

            var parameters = function_prototype.iterate(&ast);

            while (parameters.next()) |parameter| {
                const name = ast.tokenSlice(parameter.name_token orelse continue);
                const @"type" = if (parameter.type_expr != 0) ast.getNodeSource(parameter.type_expr) else "unknown";

                function.parameters.append(.{ .name = name, .type = @"type" }) catch continue;
            }
        } else if (declaration_tag == .simple_var_decl) {
            const variable_declaration = ast.simpleVarDecl(declaration_index);

            if (variable_declaration.ast.init_node == 0) continue;

            switch (nodes.items(.tag)[variable_declaration.ast.init_node]) {
                .container_decl_arg, .container_decl, .container_decl_arg_trailing, .container_decl_trailing => {},
                else => continue,
            }

            var buffer: [2]std.zig.Ast.Node.Index = undefined;
            const container_declaration = ast.fullContainerDecl(&buffer, variable_declaration.ast.init_node) orelse continue;

            if (tokens.items(.tag)[container_declaration.ast.main_token] != .keyword_enum) continue;

            const @"enum" = exports.enums.addOne() catch continue;

            @"enum".* = .{
                .doc_comment = DocComment.search(ast, main_token),
                .name = ast.tokenSlice(main_token + 1),
                .values = std.ArrayList(Enum.Value).init(ally),
            };

            for (container_declaration.ast.members) |member_index| {
                if (nodes.items(.tag)[member_index] != .container_field_init) {
                    continue;
                }

                const name = ast.tokenSlice(nodes.items(.main_token)[member_index]);
                const member_data = nodes.items(.data)[member_index];
                const number = ast.getNodeSource(member_data.rhs);

                @"enum".values.append(.{ .name = name, .number = number }) catch continue;
            }
        }
    }

    return exports;
}

const Exports = struct {
    const Self = @This();

    ally: Allocator,
    enums: std.ArrayList(Enum),
    functions: std.ArrayList(Function),

    fn init(ally: Allocator) Self {
        return .{
            .ally = ally,
            .enums = std.ArrayList(Enum).init(ally),
            .functions = std.ArrayList(Function).init(ally),
        };
    }

    fn c(self: *Self) !Bytes {
        var bytes = Bytes.init(self.ally);

        const b = &bytes;
        try b.appendSlice(
            \\#ifndef RT_CORE_H
            \\#define RT_CORE_H
            \\
            \\#include <stddef.h>
            \\#include <stdint.h>
            \\
            \\
        );

        for (self.enums.items) |e| {
            try b.appendSlice("// ");
            try b.appendSlice(e.doc_comment);
            try b.append('\n');

            try b.appendSlice("typedef enum {\n");

            for (e.values.items) |v| {
                try b.appendSlice("    ");
                try b.appendSlice(v.name);
                try b.appendSlice(" = ");
                try b.appendSlice(v.number);
                try b.appendSlice(",\n");
            }

            try b.appendSlice("} ");
            try deriveType(b, e.name);
            try b.appendSlice(";\n\n");
        }

        for (self.functions.items) |f| {
            try b.appendSlice("// ");
            try b.appendSlice(f.doc_comment);
            try b.append('\n');

            try deriveType(b, f.return_value);
            try b.append(' ');
            try deriveName(b, f.name);
            try b.append('(');

            for (f.parameters.items, 0..) |p, i| {
                try parameter(b, p.name, p.type);

                if (i != f.parameters.items.len - 1) {
                    try b.appendSlice(", ");
                }
            }

            try b.appendSlice(");\n\n");
        }

        try b.appendSlice(
            \\#endif
            \\
        );

        return bytes;
    }

    fn rust(self: *Self) !Bytes {
        return Bytes.init(self.ally);
    }

    fn js(self: *Self) !Bytes {
        return Bytes.init(self.ally);
    }

    fn parameter(b: *Bytes, name: []const u8, @"type": []const u8) !void {
        if (eql(u8, @"type", "lib.System.SimpleClock.Callback")) {
            try b.appendSlice("int64_t (*");
            try b.appendSlice(name);
            try b.appendSlice(")(void)");
        } else if (eql(u8, @"type", "lib.System.SimpleRng.Callback")) {
            try b.appendSlice("void (*");
            try b.appendSlice(name);
            try b.appendSlice(")(uint8_t* buf, ");
            try deriveType(b, "usize");
            try b.appendSlice(" length)");
        } else if (eql(u8, @"type", "Error")) {
            try reticulumType(b, @"type");
        } else {
            try deriveType(b, @"type");
        }
    }

    fn deriveType(b: *Bytes, string: []const u8) !void {
        const translations = std.StaticStringMap([]const u8).initComptime(.{
            .{ "c_int", "int" },
            .{ "anyopaque", "void" },
            .{ "*anyopaque", "void*" },
            .{ "**anyopaque", "void**" },
            .{ "u16", "uint16_t" },
            .{ "u32", "uint32_t" },
            .{ "u64", "uint64_t" },
            .{
                "usize", switch (@sizeOf(usize)) {
                    8 => "uint8_t",
                    16 => "uint16_t",
                    32 => "uint32_t",
                    64 => "uint64_t",
                    128 => "uint128_t",
                    else => "",
                },
            },
        });

        if (translations.get(string)) |translation| {
            try b.appendSlice(translation);
        } else {
            try reticulumType(b, string);
        }
    }

    fn reticulumType(b: *Bytes, string: []const u8) !void {
        try deriveName(b, string);
        try b.appendSlice("_t");
    }

    fn deriveName(b: *Bytes, string: []const u8) !void {
        try b.appendSlice("rt_core");

        if (string.len > 0 and !std.ascii.isUpper(string[0])) {
            try b.append('_');
        }

        for (string) |char| {
            if (std.ascii.isUpper(char)) {
                try b.append('_');
                try b.append(std.ascii.toLower(char));
            } else {
                try b.append(char);
            }
        }
    }
};

const Enum = struct {
    const Value = struct {
        name: []const u8,
        number: []const u8,
    };

    doc_comment: []const u8,
    name: []const u8,
    values: std.ArrayList(Value),
};

const Function = struct {
    const Parameter = struct {
        name: []const u8,
        type: []const u8,
    };

    doc_comment: []const u8,
    name: []const u8,
    parameters: std.ArrayList(Parameter),
    return_value: []const u8,
};

pub fn derive(comptime name: []const u8) []const u8 {
    if (!builtin.target.cpu.arch.isWasm()) {
        var snake_case: []const u8 = "rt_core_";

        inline for (name) |char| {
            if (std.ascii.isUpper(char)) {
                snake_case = snake_case ++ .{ '_', std.ascii.toLower(char) };
            } else {
                snake_case = snake_case ++ .{char};
            }
        }

        return snake_case;
    } else {
        return name;
    }
}
