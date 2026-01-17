const std = @import("std");
const Type = std.builtin.Type;
const Writer = std.Io.Writer;

const arg = @import("arg.zig");
const clarg = @import("clarg.zig");
const utils = @import("utils.zig");
const Span = utils.Span;
const kebabFromSnakeDash = utils.kebabFromSnakeDash;
const kebabFromSnake = utils.kebabFromSnake;

pub fn help(Args: type, writer: *Writer) !void {
    const ArgsWithHelp = arg.ArgsWithHelp(Args);

    // 2 for "--" and 2 for indentation
    const max_len = comptime arg.maxLen(ArgsWithHelp) + 4;
    const info = @typeInfo(ArgsWithHelp).@"struct";

    try printUsage(info, writer);
    try printDesc(Args, writer);
    try printCmds(info, writer, max_len);
    try printPositionals(info, writer, max_len);
    try printOptions(info, writer, max_len);
}

pub fn helpToFile(Args: type, file: std.fs.File) !void {
    var buf: [2048]u8 = undefined;
    var writer = file.writer(&buf);
    try help(Args, &writer.interface);
    return writer.interface.flush();
}

fn printUsage(info: Type.Struct, writer: *Writer) !void {
    try writer.writeAll("Usage:\n");
    try writer.print("  {s} [options] [args]\n", .{clarg.prog});

    // Check if there is at least one command
    var found = false;
    inline for (info.fields) |field| {
        if (!found and @typeInfo(field.type.Value) == .@"struct") {
            found = true;
            try writer.print("  {s} [commands] [options] [args]\n", .{clarg.prog});
        }
    }
    try writer.writeAll("\n");
}

fn printDesc(Args: type, writer: *Writer) !void {
    if (!@hasDecl(Args, "description")) return;

    try writer.writeAll("Description:\n");
    var it = std.mem.splitScalar(u8, Args.description, '\n');

    while (it.next()) |line| {
        try writer.print("  {s}\n", .{line});
    }
    try writer.writeAll("\n");
}

fn printCmds(info: Type.Struct, writer: *Writer, comptime max_len: usize) !void {
    var found = false;

    inline for (info.fields) |field| {
        if (arg.is(field, .cmd)) {
            if (!found) {
                try writer.writeAll("Commands:\n");
            }
            found = true;

            const name = comptime kebabFromSnake(field.name);
            const text = "  " ++ name;

            // Case: cmd: Arg(CmdArgs) = .{}
            if (field.defaultValue()) |def_val| {
                const desc_field = def_val.desc;
                // Case: cmd: Arg(CmdArgs) = .{ .desc = "foo" }
                if (desc_field.len > 0) {
                    var desc_line_iter = std.mem.splitScalar(u8, def_val.desc, '\n');

                    const first_line = desc_line_iter.first();
                    try writer.print(
                        "{[text]s:<[width]} {[description]s}\n",
                        .{ .text = text, .width = max_len, .description = first_line },
                    );

                    while (desc_line_iter.next()) |desc_line| {
                        try writer.print(
                            "{[text]s:<[width]} {[description]s}\n",
                            .{ .text = "", .width = max_len, .description = desc_line },
                        );
                    }
                } else {
                    try writer.print("{s}\n", .{text});
                }
            }
            // Case: cmd: Arg(CmdArgs)
            else {
                try writer.writeAll("  " ++ name ++ "\n");
            }
        }
    }

    if (found) try writer.writeAll("\n");
}

fn printPositionals(info: Type.Struct, writer: *Writer, comptime max_len: usize) !void {
    var found = false;

    inline for (info.fields) |field| {
        comptime var text: []const u8 = "  ";

        // If positional, it is case: arg: Arg(bool) = .{ .positional = true }
        // so always a default value
        if (comptime arg.is(field, .positional)) {
            const def_val = field.defaultValue().?;
            if (!found) {
                try writer.writeAll("Arguments:\n");
            }
            found = true;

            comptime text = text ++ arg.typeStr(field);

            const desc_field = @field(def_val, "desc");
            // Case: arg: Arg(bool) = .{ .desc = "foo" }
            if (desc_field.len > 0) {
                var desc_line_iter = std.mem.splitScalar(u8, def_val.desc, '\n');

                const first_line = desc_line_iter.first();
                try writer.print(
                    "{[text]s:<[width]} {[description]s}\n",
                    .{ .text = text, .width = max_len, .description = first_line },
                );

                while (desc_line_iter.next()) |desc_line| {
                    try writer.print(
                        "{[text]s:<[width]} {[description]s}\n",
                        .{ .text = "", .width = max_len, .description = desc_line },
                    );
                }
            } else {
                try writer.print("{s}", .{text});
            }

            try printDefault(field, writer);
            try additionalData(writer, field, max_len);
            try writer.writeAll("\n");
        }
    }

    if (found) try writer.writeAll("\n");
}

fn printOptions(info: Type.Struct, writer: *Writer, comptime max_len: usize) !void {
    try writer.writeAll("Options:\n");

    inline for (info.fields) |field| {
        comptime var text: []const u8 = "  ";

        if (comptime !(arg.is(field, .cmd) or arg.is(field, .positional))) {
            // Case: arg: Arg(bool) = .{}
            if (field.defaultValue()) |def_val| {
                if (def_val.short) |short| {
                    text = text ++ "-" ++ .{short} ++ ", ";
                }

                const type_text = comptime arg.typeStr(field);
                comptime text = text ++ kebabFromSnakeDash(field.name) ++ if (type_text.len > 0) " " ++ type_text else "";

                const desc_field = def_val.desc;
                // Case: arg: Arg(bool) = .{ .desc = "foo" }
                if (desc_field.len > 0) {
                    var desc_line_iter = std.mem.splitScalar(u8, def_val.desc, '\n');

                    const first_line = desc_line_iter.first();
                    try writer.print(
                        "{[text]s:<[width]} {[description]s}\n",
                        .{ .text = text, .width = max_len, .description = first_line },
                    );

                    while (desc_line_iter.next()) |desc_line| {
                        try writer.print(
                            "{[text]s:<[width]} {[description]s}\n",
                            .{ .text = "", .width = max_len, .description = desc_line },
                        );
                    }
                } else {
                    try writer.print("{s}", .{text});
                }
            }
            // Case: arg: Arg(bool)
            else {
                try writer.writeAll("  " ++ comptime kebabFromSnakeDash(field.name) ++ " " ++ arg.typeStr(field));
            }

            try printDefault(field, writer);
            try printRequired(field, writer);
            try additionalData(writer, field, max_len);

            try writer.writeAll("\n");
        }
    }
}

/// Prints argument default value if one
fn printDefault(field: Type.StructField, writer: *Writer) !void {
    if (field.type.default) |default| {
        const Def = @TypeOf(default);
        const info = @typeInfo(Def);

        if (info == .@"enum") {
            try writer.print(" [default: {t}]", .{default});
        } else if (Def == []const u8) {
            try writer.print(" [default: \"{s}\"]", .{default});
        }
        // We don't print [default: false] for bools
        else if (Def != bool) {
            try writer.print(" [default: {any}]", .{default});
        }
    }
}

/// Prints argument default value if one
fn printRequired(field: Type.StructField, writer: *Writer) !void {
    if (field.defaultValue()) |def| {
        if (def.required) {
            try writer.writeAll(" [required]");
        }
    }
}

fn additionalData(writer: *Writer, field: Type.StructField, comptime padding: usize) !void {
    const pad = " " ** (padding + 4);

    switch (@typeInfo(@field(field.type, "Value"))) {
        .@"enum" => |infos| {
            try writer.print("\n{s}Supported values:\n", .{pad});

            inline for (infos.fields, 0..) |f, i| {
                try writer.print("{s}  {s}{s}", .{
                    pad,
                    f.name,
                    if (i < infos.fields.len - 1) "\n" else "",
                });
            }
        },
        else => {},
    }
}
