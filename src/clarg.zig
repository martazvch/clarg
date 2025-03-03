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
        .comptime_int, .comptime_float => arg,
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
        // add default value after the description if there is one
        try stdout.print(
            "{s:<20}  {s}\n",
            .{ text, @field(tmp, "desc") },
        );
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
    // comptime var res: []const u8 = "";

    // @compileLog(infos);
    // @compileLog(@typeInfo(infos.child));

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
    //
    // return res;
}
