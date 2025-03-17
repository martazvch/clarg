const std = @import("std");

pub fn Arg(arg: anytype) type {
    const T: type = ArgType(arg);

    return struct {
        desc: []const u8 = "",
        short: ?[]const u8 = null,
        default: ?T = default_value(T, arg),
        positional: bool = false,
        required: bool = false,
    };
}

fn ArgType(arg: anytype) type {
    const T = @TypeOf(arg);

    if (T == @TypeOf(null))
        @compileError("Arg's default value can't be null");

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

fn default_value(T: type, arg: anytype) ?T {
    return switch (@typeInfo(@TypeOf(arg))) {
        .comptime_int, .comptime_float, .@"enum" => arg,
        else => null,
    };
}

pub fn print_help(Args: type) !void {
    const stdout = std.io.getStdOut().writer();

    if (@hasDecl(Args, "description")) {
        const desc = @field(Args, "description");
        try stdout.print("{s}\n\n", .{desc});
    }

    try stdout.writeAll("Options:\n");
    // 2 for "--" and 2 for indentation
    const len = comptime max_len(Args) + 4;

    inline for (@typeInfo(Args).@"struct".fields) |field| {
        const tmp = field.defaultValue().?;
        comptime var text: []const u8 = "  ";

        if (@field(tmp, "short")) |short|
            text = text ++ "-" ++ short ++ ", ";

        comptime text = text ++ from_snake(field.name) ++ arg_type(tmp);

        try stdout.print(
            "{[text]s:<[width]}  {[description]s}",
            .{ .text = text, .description = @field(tmp, "desc"), .width = len },
        );

        if (@field(tmp, "default")) |default| {
            if (@typeInfo(@TypeOf(default)) == .@"enum")
                try stdout.print(" [default: {s}]", .{@tagName(default)})
            else
                try stdout.print(" [default: {any}]", .{default});
        }

        try additional_data(stdout, tmp, len);
        try stdout.writeAll("\n");
    }

    try stdout.print(
        "  {[text]s:<[width]}  {[description]s}\n",
        .{ .text = "-h, --help", .description = "prints help", .width = len - 2 },
    );
}

fn from_snake(comptime text: []const u8) []const u8 {
    comptime var name: []const u8 = "--";

    inline for (text) |c|
        name = name ++ if (c == '_') "-" else .{c};

    return name;
}

fn to_snake(text: []const u8) []const u8 {
    var name: []const u8 = "";

    const State = enum { start, end };
    var state: State = .start;

    for (text) |c| {
        if (state == .start and c == '-')
            continue
        else
            state = .end;

        name = name ++ if (c == '-') '_' else c;
    }

    // s: switch (state) {
    //     .start => {
    //         continue :s .end
    //     },
    //     .end => {}
    //
    // }
    // inline for (text) |c| {
    //     if (c == )
    //     name = name ++ if (c == '_') "-" else .{c};
    // }

    return name;
}

fn arg_type(comptime field: anytype) []const u8 {
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

fn additional_data(writer: anytype, field: anytype, comptime padding: usize) !void {
    const default = @typeInfo(@TypeOf(@field(field, "default"))).optional;
    const pad = " " ** (padding + 4);

    switch (@typeInfo(default.child)) {
        .@"enum" => |infos| {
            try writer.print(
                "\n{s}Supported values:\n",
                .{pad},
            );

            inline for (infos.fields) |f|
                try writer.print(
                    "{s}  {s}\n",
                    .{ pad, f.name },
                );
        },
        else => {},
    }
}

fn max_len(Args: type) usize {
    var len: usize = 0;

    inline for (@typeInfo(Args).@"struct".fields) |field| {
        if (field.name.len > len) len = field.name.len;
    }

    return len;
}

pub fn parse(args: *std.process.ArgIterator, Args: type) !Args {
    // Program name
    _ = args.next();

    while (args.next()) |arg| {
        std.debug.print("Arg: {s}\n", .{to_snake(arg)});
    }
    return .{};
}
