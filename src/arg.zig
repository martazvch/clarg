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
    if (T == void) {
        @compileError("Arg's type can't be void");
    }

    return switch (@typeInfo(T)) {
        .@"enum" => T,
        .enum_literal => switch (arg) {
            .string => []const u8,
            else => @compileError("Only '.string' is allowed as enum literal, found " ++ @tagName(arg)),
        },
        .comptime_int => i64,
        .comptime_float => f64,
        .pointer => |ptr| b: {
            const info = @typeInfo(ptr.child);
            if (info != .array) {
                @compileError("Only slices are allowed for pointers");
            }
            if (info.array.child != u8) {
                @compileError("Only slices of 'u8' are allowed");
            }

            break :b []const u8;
        },
        .type => arg,
        else => @compileError("Unsupported arg type: " ++ @typeName(arg)),
    };
}

/// If the arg is already a type, return it, otherwise get default value
fn defaultValue(T: type, arg: anytype) ?T {
    const info = @typeInfo(@TypeOf(arg));
    return if (info != .type and info != .enum_literal) arg else null;
}

pub fn typeStr(field: anytype) []const u8 {
    const default = @field(field, "default");
    const infos = @typeInfo(@TypeOf(default)).optional;

    return switch (@typeInfo(infos.child)) {
        .bool => "",
        .int => " <int>",
        .float => " <float>",
        .@"enum" => " <enum>",
        .pointer => " <string>",
        else => unreachable,
    };
}

/// Given a structure defining our arguments, returns the string size needed
/// to write the longest one with its type
pub fn maxLen(Args: type) usize {
    if (@typeInfo(Args) != .@"struct") {
        @compileError("Maximum length calculation of fields can only be done on structures");
    }

    var len: usize = 0;

    inline for (@typeInfo(Args).@"struct".fields) |field| {
        const type_len = if (field.defaultValue()) |def| typeStr(def).len else 0;
        len = @max(len, field.name.len + type_len);
    }

    return len;
}
