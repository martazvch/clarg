const std = @import("std");
const Type = std.builtin.Type;
const Writer = std.Io.Writer;

const utils = @import("utils.zig");
const StructProto = utils.StructProto;
const Span = utils.Span;
const fromSnake = utils.fromSnake;

const arg = @import("arg.zig");
const Diag = @import("Diag.zig");

const Error = error{ AlreadyParsed, WrongValueType, UnknownArg, CmdAfterOpts };

var prog_name: ?[]const u8 = null;

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

/// Parses arguments from the iterator. It must declare a function `next` returning
/// either `?[]const u8` or `?[:0]const u8`
pub fn parse(Args: type, args_iter: anytype, diag: *Diag) (std.Io.Writer.Error || Error)!arg.ParsedArgs(Args) {
    validateIter(args_iter);

    if (@typeInfo(Args) != .@"struct") {
        @compileError("Arguments type must be a structure");
    }

    prog_name = args_iter.next();

    var options_started = false;
    var parsed_positional: usize = 0;
    var res = arg.ParsedArgs(Args){};
    var proto: StructProto(Args) = .{};
    const infos = @typeInfo(Args).@"struct";

    a: while (args_iter.next()) |argument| {
        // constCast allow to modify the text inplace to avoid allocation to convert from kebab-cli-syntax
        // to snake_case structure fields syntaxe
        const arg_parsed = getNameAndValueRanges(@constCast(argument));
        const name = arg_parsed.name.getText(argument);

        // if (arg_parsed.is_cmd) {
        //     if (options_started) {
        //         try diag.print("Found command '{s}' after options", .{name});
        //         return error.CmdAfterOpts;
        //     }
        //
        //     inline for (infos.fields) |field| {
        //         if (comptime arg.is(field, .cmd)) {
        //             if (std.mem.eql(u8, field.name, name)) {
        //                 @field(res, field.name) = try parse(field.type.Value, args_iter, diag);
        //             }
        //         }
        //     }
        // }

        options_started = true;

        inline for (infos.fields) |field| {
            if (matchField(field, arg_parsed.name.getTextEx(argument))) {
                if (@field(proto, field.name)) {
                    try diag.print("Already parsed argument '{s}' (or its long/short version)", .{name});
                    return error.AlreadyParsed;
                } else {
                    if (arg_parsed.value) |range| {
                        @field(res, field.name) = argValue(@field(field.type, "Value"), range.getText(argument)) catch {
                            try diag.print("Expect a value of type '{s}' for argument '{s}'", .{ arg.typeStr(field), name });
                            return error.WrongValueType;
                        };
                    }
                    // If it's a boolean flag, no value needed
                    else if (field.type.Value == bool) {
                        @field(res, field.name) = true;
                    }

                    @field(proto, field.name) = true;
                    continue :a;
                }
            }
        }

        // Try positional
        var count: usize = 0;

        inline for (infos.fields) |field| {
            if (field.defaultValue()) |def| {
                if (def.positional) {
                    if (count == parsed_positional) {
                        @field(res, field.name) = argValue(@field(field.type, "Value"), argument) catch {
                            try diag.print("Expect a value of type '{s}' for argument '{s}'", .{ arg.typeStr(field), name });
                            return error.WrongValueType;
                        };

                        parsed_positional += 1;
                        continue :a;
                    }

                    count += 1;
                }
            }
        }

        try diag.print("Unknown argument '{s}'", .{name});
        return error.UnknownArg;
    }

    return res;
}

fn matchField(field: Type.StructField, arg_name: Span.ToSource) bool {
    return switch (arg_name) {
        .long => |n| std.mem.eql(u8, field.name, n),
        .short => |n| matchFieldShort(field, n),
    };
}

fn matchFieldShort(field: Type.StructField, arg_name: u8) bool {
    if (field.defaultValue()) |def| {
        if (@field(def, "short")) |short| {
            if (short == arg_name) {
                return true;
            }
        }
    }

    return false;
}

/// Performs some comptime type checking on argument iterator
fn validateIter(iter: anytype) void {
    const T = @TypeOf(if (@typeInfo(@TypeOf(iter)) == .pointer) iter.* else iter);

    if (!@hasDecl(T, "next")) {
        @compileError("cli_args's type must have a `next` function");
    }
    const ret_type = @typeInfo(@TypeOf(@field(T, "next"))).@"fn".return_type;

    if (ret_type != ?[]const u8 and ret_type != ?[:0]const u8) {
        @compileError("`next` function must return a `[]const u8` or a `[:0]const u8`");
    }
}

fn argValue(T: type, value: []const u8) error{TypeMismatch}!T {
    return switch (T) {
        i64 => std.fmt.parseInt(i64, value, 10) catch error.TypeMismatch,
        f64 => std.fmt.parseFloat(f64, value) catch error.TypeMismatch,
        []const u8 => value,
        else => switch (@typeInfo(T)) {
            .@"enum" => return std.meta.stringToEnum(T, value) orelse error.TypeMismatch,
            else => @panic("Unsupported value type: " ++ @typeName(T)),
        },
    };
}

const ParsedArgRes = struct {
    name: Span,
    value: ?Span,
    is_short: bool,
    is_cmd: bool,
};

/// Modifies inplace the text to avoid allocation
fn getNameAndValueRanges(text: []u8) ParsedArgRes {
    const State = enum { start, name, value };

    var quote = false;
    var dashes: usize = 0;
    var current: usize = 0;
    var name: Span = .{ .end = text.len };
    var value: ?Span = null;

    s: switch (State.start) {
        .start => {
            if (text[current] != '-') {
                name.start = current;
                continue :s .name;
            }
            dashes += 1;
            current += 1;
            continue :s .start;
        },
        .name => {
            if (current == text.len) break :s;
            if (text[current] == '-') text[current] = '_';
            if (text[current] == '=') {
                name.end = current;
                current += 1;

                // Ignore quotes in string case
                if (text[current] == '"') {
                    quote = true;
                    current += 1;
                }

                continue :s .value;
            }

            current += 1;
            continue :s .name;
        },
        .value => value = .{ .start = current, .end = if (quote) text.len - 1 else text.len },
    }

    return .{ .name = name, .value = value, .is_short = dashes == 1, .is_cmd = text[0] != '-' };
}

// ------
//  Help
// ------
pub fn printHelp(Args: type) !void {
    var buf: [2048]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch unreachable;

    try printHelpToStream(Args, stdout);
}

pub fn printHelpToStream(Args: type, stream: *std.Io.Writer) !void {
    // 2 for "--" and 2 for indentation
    const max_len = comptime arg.maxLen(Args) + 4;
    const info = @typeInfo(Args).@"struct";

    // TODO: error
    const name = prog_name orelse @panic("Should parse args before printing help");
    try printUsage(name, info, stream);
    try printDesc(Args, stream);
    try printCmds(info, stream, max_len);
    try printPositionals(info, stream, max_len);
    try printOptions(info, stream, max_len);
}

fn printUsage(name: []const u8, info: Type.Struct, stream: *Writer) !void {
    try stream.writeAll("Usage:\n");
    try stream.print("  {s} [options] [args]\n", .{name});

    var found = false;
    inline for (info.fields) |field| {
        if (!found and @typeInfo(field.type.Value) == .@"struct") {
            found = true;
            try stream.print("  {s} [command] [options] [args]\n", .{name});
        }
    }
    try stream.writeAll("\n");
}

fn printDesc(Args: type, stream: *Writer) !void {
    if (!@hasDecl(Args, "description")) return;
    try stream.writeAll("Description:\n");
    var it = std.mem.splitScalar(u8, Args.description, '\n');

    while (it.next()) |line| {
        try stream.print("  {s}\n", .{line});
    }
    try stream.writeAll("\n");
}

fn printCmds(info: Type.Struct, stream: *Writer, comptime max_len: usize) !void {
    var found = false;

    inline for (info.fields) |field| {
        if (arg.is(field, .cmd)) {
            if (!found) {
                try stream.writeAll("Commands:\n");
            }
            found = true;

            if (field.defaultValue()) |def_val| {
                const desc_field = def_val.desc;
                if (desc_field.len > 0) {
                    try stream.print(
                        "  {[text]s:<[width]}  {[description]s}",
                        .{ .text = field.name, .description = def_val.desc, .width = max_len },
                    );
                } else {
                    try stream.print("  {s}", .{field.name});
                }
            } else {
                try stream.writeAll("  " ++ field.name);
            }

            try stream.writeAll("\n");
        }
    }

    if (found) try stream.writeAll("\n");
}

fn printPositionals(info: Type.Struct, stream: *Writer, comptime max_len: usize) !void {
    var found = false;

    inline for (info.fields) |field| {
        comptime var text: []const u8 = "  ";

        if (field.defaultValue()) |def_val| {
            if (comptime arg.is(field, .positional)) {
                if (!found) {
                    try stream.writeAll("Arguments:\n");
                }
                found = true;

                comptime text = text ++ arg.typeStr(field);

                const desc_field = @field(def_val, "desc");
                if (desc_field.len > 0) {
                    try stream.print(
                        "{[text]s:<[width]}  {[description]s}",
                        .{ .text = text, .description = def_val.desc, .width = max_len },
                    );
                } else {
                    try stream.print("{s}", .{text});
                }

                try printDefault(field, stream);
                try additionalData(stream, field, max_len);
                try stream.writeAll("\n");
            }
        }
    }

    if (found) try stream.writeAll("\n");
}

fn printOptions(info: Type.Struct, stream: *Writer, comptime max_len: usize) !void {
    try stream.writeAll("Options:\n");

    inline for (info.fields) |field| {
        comptime var text: []const u8 = "  ";

        if (comptime !(arg.is(field, .cmd) or arg.is(field, .positional))) {
            if (field.defaultValue()) |def_val| {
                if (def_val.short) |short| {
                    text = text ++ "-" ++ .{short} ++ ", ";
                }

                comptime text = text ++ fromSnake(field.name) ++ " " ++ arg.typeStr(field);

                const desc_field = def_val.desc;
                if (desc_field.len > 0) {
                    try stream.print(
                        "{[text]s:<[width]}  {[description]s}",
                        .{ .text = text, .description = def_val.desc, .width = max_len },
                    );
                } else {
                    try stream.print("{s}", .{text});
                }
            } else {
                try stream.writeAll("  " ++ comptime fromSnake(field.name) ++ " " ++ arg.typeStr(field));
            }

            try printDefault(field, stream);
            try additionalData(stream, field, max_len);

            try stream.writeAll("\n");
        }
    }
}

fn printDefault(field: Type.StructField, stream: *Writer) !void {
    if (@field(field.type, "default")) |default| {
        const Def = @TypeOf(default);
        const info = @typeInfo(Def);

        if (info == .@"enum") {
            try stream.print(" [default: {t}]", .{default});
        } else if (Def == []const u8) {
            try stream.print(" [default: \"{s}\"]", .{default});
        }
        // We don't print [default: false] for bools
        else if (Def != bool) {
            try stream.print(" [default: {any}]", .{default});
        }
    }
}
