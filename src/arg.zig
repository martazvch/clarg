const std = @import("std");
const StructField = std.builtin.Type.StructField;

pub fn Arg(arg: anytype) type {
    return struct {
        desc: []const u8 = "",
        short: ?u8 = null,
        positional: bool = false,
        required: bool = false,

        pub const Value: type = ArgType(arg);
        pub const default: ?Value = makeDefault(Value, arg);
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
        .bool => @compileError("bool literal values aren't necessary, just use 'bool' type as argument"),
        else => @compileError("Unsupported arg type: " ++ @typeName(arg)),
    };
}

/// If the arg is already a type, return it, otherwise get default value
fn makeDefault(T: type, arg: anytype) ?T {
    const info = @typeInfo(@TypeOf(arg));
    if (T == bool) return false;
    if (info == .pointer) return arg; // for strings

    return if (info != .type and info != .enum_literal) arg else null;
}

/// Checks wether an argument needs to be defined (no default value and required argument)
pub fn mandatory(field: StructField) bool {
    const def = field.defaultValue().?;
    return def.default == null and def.required;
}

/// Checks wether an argument needs a value. Only `bool` arguments don't need one
pub fn needsValue(field: StructField) bool {
    return field.type.Value != bool;
}

pub fn typeStr(field: StructField) []const u8 {
    return switch (@typeInfo(@field(field.type, "Value"))) {
        .bool => "",
        .int => "<int>",
        .float => "<float>",
        .@"enum" => "<enum>",
        .array, .pointer => "<string>",
        .@"struct" => "",
        else => unreachable,
    };
}

pub fn is(field: StructField, kind: enum { positional, cmd }) bool {
    return switch (kind) {
        .cmd => @typeInfo(field.type.Value) == .@"struct",
        .positional => {
            const def = field.defaultValue() orelse return false;
            return def.positional;
        },
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
        // +1 for space between name and type
        var field_len = typeStr(field).len + 1;
        if (field.defaultValue()) |def| if (@field(def, "short") != null) {
            // 4 for this: '-c, ' and 1 for space between name and type
            field_len += 4;
        };

        len = @max(len, field.name.len + field_len);
    }

    return len;
}

/// Creates a structure with only the fields names and values. Final result of parsing arguments
/// Adds a 'help' field
pub fn ParsedArgs(Args: type) type {
    if (@typeInfo(Args) != .@"struct") {
        @compileError("ParsedArgs can only be used on structures");
    }

    const info = @typeInfo(Args).@"struct";

    var fields: [info.fields.len]StructField = undefined;

    inline for (info.fields, 0..) |f, i| {
        const Value = f.type.Value;

        const T, const val = b: {
            const def = f.type.default orelse break :b .{ ?Value, @as(?Value, null) };
            break :b .{ Value, def };
        };

        // https://ziggit.dev/t/error-comptime-dereference-requires-0-const-u8-to-have-a-well-defined-layout/8200/2
        fields[i] = .{
            .name = f.name,
            .type = T,
            .default_value_ptr = if (T == []const u8) @ptrCast(@as(*const []const u8, &val)) else &val,
            .is_comptime = false,
            .alignment = @alignOf(T),
        };
    }

    return @Type(.{ .@"struct" = .{
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
        .layout = .auto,
    } });
}
