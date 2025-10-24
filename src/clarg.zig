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

fn additionalData(writer: *Writer, field: anytype, comptime padding: usize) !void {
    const default = @typeInfo(@TypeOf(@field(field, "default"))).optional;
    const pad = " " ** (padding + 4);

    switch (@typeInfo(default.child)) {
        .@"enum" => |infos| {
            try writer.print("\n{s}Supported values:\n", .{pad});

            inline for (infos.fields) |f| {
                try writer.print("{s}  {s}\n", .{ pad, f.name });
            }
        },
        else => {},
    }
}

pub fn parse(cli_args: *std.process.ArgIterator, Args: type) !Args {
    // Program name
    _ = cli_args.next();

    var res = Args{};
    var proto: StructProto(Args) = .{};
    const infos = @typeInfo(Args).@"struct";

    while (cli_args.next()) |cli_arg| {
        const name_range, const value_range = getNameAndValueRanges(@constCast(cli_arg));

        const name = name_range.getText(cli_arg);

        if (value_range) |range| {
            _ = range; // autofix
        }

        inline for (infos.fields) |field| if (std.mem.eql(u8, field.name, name)) {
            if (@field(proto, field.name)) {
                // TODO: error handling
                @panic("Already parsed option");
            } else {
                @field(proto, field.name) = true;
            }

            @field(res, field.name) = undefined;
        };
    }

    return res;
}

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

        comptime text = text ++ fromSnake(field.name) ++ arg.typeStr(def_val);

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
            } else {
                try stream.print(" [default: {any}]", .{default});
            }
        }

        try additionalData(stream, def_val, len);
        try stream.writeAll("\n");
    }

    try stream.print(
        "  {[text]s:<[width]}  {[description]s}",
        .{ .text = "-h, --help", .description = "prints help", .width = len - 2 },
    );
}
