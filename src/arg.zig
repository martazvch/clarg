const std = @import("std");
const StructField = std.lang.Type.Struct.FieldAttributes;

pub fn Arg(arg: anytype) type {
    return struct {
        desc: []const u8 = "",
        short: ?u8 = null,
        positional: bool = false,
        required: bool = false,

        /// Allow to store subcommands type to parse recursively
        pub const Declared = if (@typeInfo(arg) == .@"struct") arg else @TypeOf(arg);
        /// Value's type
        pub const Value: type = ArgType(arg);
        /// Default value made from what we have inside 'Arg(...)'
        pub const default: ?Value = makeDefault(Value, arg);
    };
}

fn ArgType(arg: anytype) type {
    // If it's a type (no default value)
    if (@TypeOf(arg) == type) {
        if (arg == void) {
            @compileError("Arg's type can't be void");
        }

        return switch (@typeInfo(arg)) {
            // If it's a structure, it means it's a commands If so, we get parsing result as type
            .@"struct" => ParsedArgs(arg),
            else => arg,
        };
    }

    const T = @TypeOf(arg);

    if (T == @TypeOf(null)) {
        @compileError("Arg's default value can't be null");
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
pub fn mandatory(field: StructField, ty: type) bool {
    const def = field.defaultValue(ty).?;
    return def.default == null and def.required;
}

/// Checks wether an argument needs a value. Only `bool` arguments don't need one
pub fn needsValue(Field: type) bool {
    return Field.Value != bool;
}

pub fn typeStr(Field: type) []const u8 {
    return switch (@typeInfo(@field(Field, "Value"))) {
        .bool => "",
        .int => "<int>",
        .float => "<float>",
        .@"enum" => "<enum>",
        .array, .pointer => "<string>",
        .@"struct" => "",
        else => unreachable,
    };
}

pub fn is(comptime field: StructField, ty: type, kind: enum { positional, cmd }) bool {
    return switch (kind) {
        .cmd => return @typeInfo(ty.Value) == .@"struct",
        .positional => {
            const def = field.defaultValue(ty) orelse return false;
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
    const info = @typeInfo(Args).@"struct";

    inline for (info.field_names, info.field_types, info.field_attrs) |name, ty, attr| {
        // +1 for space between name and type
        var field_len = typeStr(ty).len + 1;
        if (attr.defaultValue(ty)) |def| if (@field(def, "short") != null) {
            // 4 for this: '-c, ' and 1 for space between name and type
            field_len += 4;
        };

        len = @max(len, name.len + field_len);
    }

    return len;
}

/// Creates a structure with only the fields names and values. Final result of parsing arguments
pub fn ParsedArgs(Args1: type) type {
    const Args = ArgsWithHelp(Args1);

    const info = @typeInfo(Args).@"struct";
    var field_names: [info.field_names.len][]const u8 = undefined;
    var field_types: [info.field_types.len]type = undefined;
    var field_attrs: [info.field_attrs.len]std.builtin.Type.Struct.FieldAttributes = undefined;

    inline for (info.field_names, info.field_types, info.field_attrs, 0..) |name, ty, attr, i| {
        const T, const val = b: {
            // We're in this case when parsing a subcommand
            // When declared, the `Value` field is computed and types are no longer arg.Arg(...)
            // but the raw type inside
            if (@typeInfo(ty) != .@"struct") {
                break :b .{ ty, attr.default_value_ptr };
            }

            // Get value's type
            const Value = ty.Value;
            const def = ty.default orelse {
                // If no default value, we emit a `null` casted to the correct type
                if (is(attr, ty, .cmd)) {
                    const T = ParsedArgs(ty.Value);
                    break :b .{ ?T, @as(?T, null) };
                }

                // If there is a default value of the Arg structure (Arg(..) = .{...})
                // we check if the argument is required. If so, we don't mark it's type as optional
                if (attr.defaultValue(ty)) |default| {
                    // If we parse a subcommand, there are no struct anymore but the raw type
                    if (@typeInfo(@TypeOf(default)) == .@"struct") {
                        if (default.required) {
                            break :b .{ Value, @as(Value, undefined) };
                        }
                    }
                }

                // Otherwise we emit a null casted to the correct type
                break :b .{ ?Value, @as(?Value, null) };
            };

            break :b .{ Value, def };
        };

        // https://ziggit.dev/t/error-comptime-dereference-requires-0-const-u8-to-have-a-well-defined-layout/8200/2
        field_names[i] = name;
        field_types[i] = T;
        field_attrs[i] = .{
            .default_value_ptr = if (@TypeOf(val) == ?*const anyopaque)
                val
            else if (T == []const u8)
                @ptrCast(@as(*const []const u8, &val))
            else
                &val,
        };
    }

    return @Struct(
        .auto,
        null,
        &field_names,
        &field_types,
        &field_attrs,
    );
}

/// Adds a 'help' field if not user-defined
pub fn ArgsWithHelp(Args: type) type {
    if (@typeInfo(Args) != .@"struct") {
        @compileError("ParsedArgs can only be used on structures");
    }
    const info = @typeInfo(Args).@"struct";

    inline for (info.field_names) |name| {
        if (std.mem.eql(u8, name, "help")) {
            return Args;
        }
    }

    var field_names: [info.field_names.len + 1][]const u8 = undefined;
    var field_types: [info.field_types.len + 1]type = undefined;
    var field_attrs: [info.field_attrs.len + 1]StructField = undefined;

    inline for (info.field_names, info.field_types, info.field_attrs, 0..) |name, ty, attr, i| {
        field_names[i] = name;
        field_types[i] = ty;
        field_attrs[i] = .{
            .default_value_ptr = attr.default_value_ptr,
        };
    }

    field_names[info.field_names.len] = "help";
    field_types[info.field_types.len] = Arg(bool);
    field_attrs[info.field_attrs.len] = .{
        .default_value_ptr = &Arg(bool){
            .desc = "Prints this help and exit",
            .short = 'h',
        },
    };

    return @Struct(
        .auto,
        null,
        &field_names,
        &field_types,
        &field_attrs,
    );
}
