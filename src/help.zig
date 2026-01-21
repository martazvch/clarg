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
            const name_text = "  " ++ name;

            // Case: cmd: Arg(CmdArgs) = .{}
            if (field.defaultValue()) |def_val| {
                const desc_field = def_val.desc;
                // Case: cmd: Arg(CmdArgs) = .{ .desc = "foo" }
                if (desc_field.len > 0) {
                    try printMultiline(writer, name_text, def_val.desc, max_len);
                } else {
                    try writer.print("{s}\n", .{name_text});
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
        comptime var name_text: []const u8 = "  ";

        // If positional, it is case: arg: Arg(bool) = .{ .positional = true }
        // so always a default value
        if (comptime arg.is(field, .positional)) {
            const def_val = field.defaultValue().?;
            if (!found) {
                try writer.writeAll("Arguments:\n");
            }
            found = true;

            comptime name_text = name_text ++ arg.typeStr(field);

            const desc_field = @field(def_val, "desc");
            // Case: arg: Arg(bool) = .{ .desc = "foo" }
            if (desc_field.len > 0) {
                try printMultiline(writer, name_text, desc_field, max_len);
            } else {
                try writer.print("{s}", .{name_text});
            }

            try addExtraInfo(writer, field, max_len, .{ .required = false, .pad = desc_field.len > 0 });
        }
    }

    if (found) try writer.writeAll("\n");
}

fn printOptions(info: Type.Struct, writer: *Writer, comptime max_len: usize) !void {
    try writer.writeAll("Options:\n");

    inline for (info.fields) |field| {
        comptime var name_text: []const u8 = "  ";

        if (comptime !(arg.is(field, .cmd) or arg.is(field, .positional))) {
            var pad = false;

            // Case: arg: Arg(bool) = .{}
            if (field.defaultValue()) |def_val| {
                if (def_val.short) |short| {
                    name_text = name_text ++ "-" ++ .{short} ++ ", ";
                }

                const type_text = comptime arg.typeStr(field);
                comptime name_text = name_text ++ kebabFromSnakeDash(field.name) ++ if (type_text.len > 0) " " ++ type_text else "";

                const desc_field = def_val.desc;
                // Case: arg: Arg(bool) = .{ .desc = "foo" }
                if (desc_field.len > 0) {
                    try printMultiline(writer, name_text, def_val.desc, max_len);
                    pad = true;
                } else {
                    try writer.print("{s}", .{name_text});
                }
            }
            // Case: arg: Arg(bool)
            else {
                try writer.writeAll("  " ++ comptime kebabFromSnakeDash(field.name) ++ " " ++ arg.typeStr(field));
            }

            try addExtraInfo(writer, field, max_len, .{ .pad = pad });
        }
    }
}

const ExtraOpts = struct {
    default: bool = true,
    required: bool = true,
    additional: bool = true,
    pad: bool,
};
fn addExtraInfo(writer: *Writer, field: Type.StructField, comptime max_len: usize, opts: ExtraOpts) !void {
    var buf: [1024]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);

    if (opts.default) {
        try printDefault(&w, field);
    }
    if (opts.required) {
        try printRequired(&w, field);
    }
    const extra = w.buffered();
    if (extra.len > 0) {
        if (opts.pad) {
            try writer.print("{[padding]s:>[len]}", .{ .padding = " ", .len = max_len + 5 });
        }
        try writer.writeAll(extra);
        try writer.writeAll("\n");
    } else if (!opts.pad) {
        // We just insert new line
        try writer.writeAll("\n");
    }

    if (opts.additional) {
        try additionalData(writer, field, max_len);
    }
}

/// Prints argument default value if one
fn printDefault(writer: *Writer, field: Type.StructField) !void {
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
fn printRequired(writer: *Writer, field: Type.StructField) !void {
    if (field.defaultValue()) |def| {
        if (def.required) {
            try writer.writeAll(" [required]");
        }
    }
}

fn additionalData(writer: *Writer, field: Type.StructField, comptime padding: usize) !void {
    const pad = " " ** (padding + 6);

    switch (@typeInfo(@field(field.type, "Value"))) {
        .@"enum" => |infos| {
            try writer.print("{s}Supported values:\n", .{pad});

            inline for (infos.fields) |f| {
                try writer.print("{s}    {s}\n", .{ pad, f.name });
            }
        },
        else => {},
    }
}

/// Handles multiline descriptions. Returns `true` if multiple lines were printed
fn printMultiline(writer: *Writer, name: []const u8, desc: []const u8, comptime max_len: usize) !void {
    var iter = std.mem.splitScalar(u8, desc, '\n');
    var count: usize = 0;

    while (iter.next()) |desc_line| : (count += 1) {
        try writer.print(
            "{[name]s:<[width]}  {[description]s}\n",
            .{ .name = if (count == 0) name else "", .width = max_len, .description = desc_line },
        );
    }
}
