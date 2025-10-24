const std = @import("std");

pub fn Arg(arg: anytype) type {
    const T: type = ArgType(arg);

    return struct {
        desc: []const u8 = "",
        short: ?u8 = null,
        default: ?T = defaultValue(T, arg),
        positional: bool = false,
        required: bool = false,
    };
}

fn ArgType(arg: anytype) type {
    const T = @TypeOf(arg);

    if (T == @TypeOf(null)) {
        @compileError("Arg's default value can't be null");
    }

    return if (@typeInfo(T) == .type)
        arg
    else switch (@typeInfo(T)) {
        .@"enum" => T,
        .enum_literal => switch (arg) {
            .string => []const u8,
            else => @compileError("Only '.string' is allowed as enum literal, found " ++ @tagName(arg)),
        },
        .comptime_int => i64,
        .comptime_float => f64,
        else => @compileError("Unsupported arg type: " ++ @typeName(arg)),
    };
}

fn defaultValue(T: type, arg: anytype) ?T {
    return switch (@typeInfo(@TypeOf(arg))) {
        .comptime_int, .comptime_float, .@"enum" => arg,
        else => null,
    };
}

pub fn printHelp(Args: type) !void {
    var buf: [2048]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch unreachable;

    if (@hasDecl(Args, "description")) {
        const desc = @field(Args, "description");
        try stdout.print("{s}\n\n", .{desc});
    }

    try stdout.writeAll("Options:\n");
    // 2 for "--" and 2 for indentation
    const len = comptime maxLen(Args) + 4;

    inline for (@typeInfo(Args).@"struct".fields) |field| {
        const tmp = field.defaultValue().?;
        comptime var text: []const u8 = "  ";

        if (@field(tmp, "short")) |short| {
            text = text ++ "-" ++ .{short} ++ ", ";
        }

        comptime text = text ++ fromSnake(field.name) ++ argType(tmp);

        try stdout.print(
            "{[text]s:<[width]}  {[description]s}",
            .{ .text = text, .description = @field(tmp, "desc"), .width = len },
        );

        if (@field(tmp, "default")) |default| {
            if (@typeInfo(@TypeOf(default)) == .@"enum") {
                try stdout.print(" [default: {t}]", .{default});
            } else {
                try stdout.print(" [default: {any}]", .{default});
            }
        }

        try additionalData(stdout, tmp, len);
        try stdout.writeAll("\n");
    }

    try stdout.print(
        "  {[text]s:<[width]}  {[description]s}\n",
        .{ .text = "-h, --help", .description = "prints help", .width = len - 2 },
    );
}

fn fromSnake(comptime text: []const u8) []const u8 {
    comptime var name: []const u8 = "--";

    inline for (text) |c| {
        name = name ++ if (c == '_') "-" else .{c};
    }

    return name;
}

fn argType(comptime field: anytype) []const u8 {
    const default = @field(field, "default");
    const infos = @typeInfo(@TypeOf(default)).optional;

    return switch (@typeInfo(infos.child)) {
        .bool => "",
        .int => " <int>",
        .float => " <float>",
        .@"enum" => " <enum>",
        .pointer => |ptr| blk: {
            if (ptr.child != u8)
                @compileError("Only slices of 'u8' are supported")
            else
                break :blk " <string>";
        },
        else => @compileError("Default value must be bool, enum or strings"),
    };
}

fn additionalData(writer: anytype, field: anytype, comptime padding: usize) !void {
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

fn maxLen(Args: type) usize {
    var len: usize = 0;

    inline for (@typeInfo(Args).@"struct".fields) |field| {
        if (field.name.len > len) len = field.name.len;
    }

    return len;
}

pub fn parse(args: *std.process.ArgIterator, Args: type) !Args {
    // Program name
    _ = args.next();

    var res = Args{};
    const infos = @typeInfo(Args).@"struct";

    while (args.next()) |arg| {
        const name_range, const value_range = getNameAndValueRanges(@constCast(arg));

        const name = name_range.getText(arg);
        std.debug.print("Arg: {s}\n", .{name});

        if (value_range) |range| {
            std.debug.print("Value: {s}\n", .{range.getText(arg)});
        }

        inline for (infos.fields) |field| if (std.mem.eql(u8, field.name, name)) {
            std.debug.print("OUI!\n", .{});
            @field(res, field.name) = undefined;
        };
    }
    return .{};
}

const Range = struct {
    start: usize = 0,
    end: usize = 0,

    pub fn getText(self: Range, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

fn getNameAndValueRanges(text: []u8) struct { Range, ?Range } {
    const State = enum { start, name, value };

    var current: usize = 0;
    var name_range: Range = .{ .end = text.len };
    var value_range: ?Range = null;

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
