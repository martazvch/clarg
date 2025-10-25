const std = @import("std");
const Type = std.builtin.Type;
const Writer = std.Io.Writer;

// Exported from build system into clarg module
const arg = @import("arg.zig");
pub const Arg = arg.Arg;

const utils = @import("utils.zig");
const StructProto = utils.StructProto;
const Span = utils.Span;
const fromSnake = utils.fromSnake;

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
pub fn parse(Args: type, args_iter: anytype) !arg.ParsedArgs(Args) {
    // anytype validation
    {
        const T = @TypeOf(if (@typeInfo(@TypeOf(args_iter)) == .pointer) args_iter.* else args_iter);

        if (!@hasDecl(T, "next")) {
            @compileError("cli_args's type must have a `next` function");
        }
        const ret_type = @typeInfo(@TypeOf(@field(T, "next"))).@"fn".return_type;

        if (ret_type != ?[]const u8 and ret_type != ?[:0]const u8) {
            @compileError("`next` function must return a `[]const u8` or a `[:0]const u8`");
        }
    }

    if (@typeInfo(Args) != .@"struct") {
        @compileError("Arguments type must be a structure");
    }

    // Program name
    _ = args_iter.next();

    var res = arg.ParsedArgs(Args){};
    var proto: StructProto(Args) = .{};
    const infos = @typeInfo(Args).@"struct";

    while (args_iter.next()) |argument| {
        // constCast allow to modify the text inplace to avoid allocation to convert from kebab-cli-syntax
        // to snake_case structure fields syntaxe
        const name_range, const value_range = getNameAndValueRanges(@constCast(argument));

        const name = name_range.getText(argument);

        inline for (infos.fields) |field| if (std.mem.eql(u8, field.name, name)) {
            if (@field(proto, field.name)) {
                // TODO: error handling
                @panic("Already parsed option");
            } else {
                if (value_range) |range| {
                    @field(res, field.name) = argValue(@field(field.type, "Value"), range.getText(argument)) catch {
                        @panic("Wrong type");
                    };
                }
                // Otherwise check if value was mandatory
                else if (arg.needsValue(field)) {
                    @panic("This field needs a value");
                }

                @field(proto, field.name) = true;
            }
        };
    }

    return res;
}

fn argValue(T: type, value: []const u8) error{TypeMismatch}!T {
    return switch (T) {
        i64 => std.fmt.parseInt(i64, value, 10) catch error.TypeMismatch,
        else => |E| {
            std.log.debug("Got type: {s}", .{@typeName(E)});
            unreachable;
        },
    };
}

/// Modifies inplace the text to avoid allocation
fn getNameAndValueRanges(text: []u8) struct { Span, ?Span } {
    const State = enum { start, name, value };

    var current: usize = 0;
    var name_range: Span = .{ .end = text.len };
    var value_range: ?Span = null;

    s: switch (State.start) {
        .start => {
            if (text[current] != '-') {
                name_range.start = current;
                continue :s .name;
            }
            current += 1;
            continue :s .start;
        },
        .name => {
            if (current == text.len) break :s;
            if (text[current] == '-') text[current] = '_';
            if (text[current] == '=') {
                name_range.end = current;
                current += 1;
                continue :s .value;
            }

            current += 1;
            continue :s .name;
        },
        .value => value_range = .{ .start = current, .end = text.len },
    }

    return .{ name_range, value_range };
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
        const def_val = field.defaultValue().?;
        comptime var text: []const u8 = "  ";

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

        if (@field(def_val, "default")) |default| {
            if (@typeInfo(@TypeOf(default)) == .@"enum") {
                try stream.print(" [default: {t}]", .{default});
            } else if (@TypeOf(default) == []const u8) {
                try stream.print(" [default: \"{s}\"]", .{default});
            }
            // We don't print [default: false] for bools
            else if (@TypeOf(default) != bool) {
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
