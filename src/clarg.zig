const std = @import("std");
const Type = std.builtin.Type;
const Writer = std.Io.Writer;

const utils = @import("utils.zig");
const StructProto = utils.StructProto;
const Span = utils.Span;
const fromSnake = utils.fromSnake;

// Exported from build system into clarg module
const arg = @import("arg.zig");
pub const Arg = arg.Arg;
pub const Diag = @import("Diagnostic.zig");
pub const SliceIter = utils.SliceIterator;

const Error = error{ AlreadyParsed, WrongValueType, UnknownArg };

fn additionalData(writer: *Writer, field: Type.StructField, comptime padding: usize) !void {
    const pad = " " ** (padding + 4);

    switch (@typeInfo(@field(field.type, "Value"))) {
        .@"enum" => |infos| {
            try writer.print("\n{s}Supported values:\n", .{pad});

            inline for (infos.fields) |f| {
                try writer.print("{s}  {s}\n", .{ pad, f.name });
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

    // Program name
    _ = args_iter.next();

    var res = arg.ParsedArgs(Args){};
    var proto: StructProto(Args) = .{};
    const infos = @typeInfo(Args).@"struct";

    a: while (args_iter.next()) |argument| {
        // constCast allow to modify the text inplace to avoid allocation to convert from kebab-cli-syntax
        // to snake_case structure fields syntaxe
        const arg_parsed = getNameAndValueRanges(@constCast(argument));
        const name = arg_parsed.name.getText(argument);

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
                    else if (@field(field.type, "Value") == bool) {
                        @field(res, field.name) = true;
                    }

                    @field(proto, field.name) = true;
                    continue :a;
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

    return .{ .name = name, .value = value, .is_short = dashes == 1 };
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
    if (@hasDecl(Args, "description")) {
        const desc = @field(Args, "description");
        try stream.print("{s}\n\n", .{desc});
    }

    try stream.writeAll("Options:\n");
    // 2 for "--" and 2 for indentation
    const len = comptime arg.maxLen(Args) + 4;

    inline for (@typeInfo(Args).@"struct".fields) |field| {
        comptime var text: []const u8 = "  ";

        if (field.defaultValue()) |def_val| {
            if (@field(def_val, "short")) |short| {
                text = text ++ "-" ++ .{short} ++ ", ";
            }

            comptime text = text ++ fromSnake(field.name) ++ arg.typeStr(field);

            const desc_field = @field(def_val, "desc");
            if (desc_field.len > 0) {
                try stream.print(
                    "{[text]s:<[width]}  {[description]s}",
                    .{ .text = text, .description = @field(def_val, "desc"), .width = len },
                );
            } else {
                try stream.print("{s}", .{text});
            }
        } else {
            try stream.writeAll("  " ++ comptime fromSnake(field.name) ++ arg.typeStr(field));
        }

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

        try additionalData(stream, field, len);
        try stream.writeAll("\n");
    }

    try stream.print(
        "  {[text]s:<[width]}  {[description]s}\n",
        .{ .text = "-h, --help", .description = "prints help", .width = len - 2 },
    );
}
