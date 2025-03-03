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
    try stdout.writeAll("General options\n\n");

    inline for (@typeInfo(Args).@"struct".fields) |field| {
        const tmp = @as(*const field.type, @alignCast(@ptrCast(field.default_value)));
        comptime var text: []const u8 = "  ";

        if (@field(tmp, "short")) |short|
            text = text ++ "-" ++ short ++ ", ";

        comptime text = text ++ arg_name(field.name) ++ arg_type(tmp);

        // TODO:
        // smart length for pretty printing
        try stdout.print(
            "{s:<20}  {s}",
            .{ text, @field(tmp, "desc") },
        );

        if (@field(tmp, "default")) |default|
            try stdout.print(" [default={any}]", .{default});

        try additional_data(stdout, tmp);
        try stdout.writeAll("\n");
    }
}

fn arg_name(comptime field: []const u8) []const u8 {
    comptime var name: []const u8 = "--";

    inline for (field) |c|
        name = name ++ if (c == '_') "-" else .{c};

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
            const array = @typeInfo(ptr.child).array;

            if (array.child != u8)
                @compileError("Only slices of 'u8' are supported")
            else
                break :blk " <string>";
        },
        else => @compileError("Default value must be bool, enum or strings"),
    };
}

fn additional_data(writer: anytype, field: anytype) !void {
    const default = @typeInfo(@TypeOf(@field(field, "default"))).optional;

    switch (@typeInfo(default.child)) {
        .@"enum" => |infos| {
            try writer.writeAll("\n    Supported values:\n");
            inline for (infos.fields) |f|
                try writer.print("        {s}\n", .{f.name});
        },
        else => {},
    }
}
