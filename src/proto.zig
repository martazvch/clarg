const std = @import("std");
const Diag = @import("Diag.zig");
const kebabFromSnake = @import("utils.zig").kebabFromSnake;

pub const Error = std.Io.Writer.Error || error{err};

/// Given a structure, generates another one with the same fields
/// with each one being `false`. Can be used as a prototype of the structure
/// to keep track of which field have been initialiazed
pub fn Proto(T: type) type {
    return struct {
        fields: ProtoFields(T) = .{},

        pub fn validate(self: *@This(), diag: *Diag) Error!void {
            const proto_info = @typeInfo(@TypeOf(self.fields)).@"struct";

            inline for (proto_info.field_names) |name| {
                const field = @field(self.fields, name);

                if (!field.done and field.required) {
                    try diag.print("Missing required argument '--{s}'", .{kebabFromSnake(name)});
                    return error.err;
                }
            }
        }
    };
}

const ProtoField = struct {
    done: bool,
    required: bool,
};

fn ProtoFields(T: type) type {
    if (@typeInfo(T) != .@"struct") {
        @compileError("StructProto can only be used on structure types");
    }

    const info = @typeInfo(T).@"struct";

    var field_names: [info.field_names.len][]const u8 = undefined;
    var field_types: [info.field_types.len]type = undefined;
    var field_attrs: [info.field_attrs.len]std.builtin.Type.Struct.FieldAttributes = undefined;

    inline for (info.field_names, info.field_types, info.field_attrs, 0..) |name, ty, attr, i| {
        const required = if (attr.defaultValue(ty)) |def|
            def.required
        else
            false;

        field_names[i] = name;
        field_types[i] = ProtoField;
        field_attrs[i] = .{
            .default_value_ptr = &ProtoField{ .done = false, .required = required },
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
