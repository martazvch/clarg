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

            inline for (proto_info.fields) |f| {
                const field = @field(self.fields, f.name);

                if (!field.done and field.required) {
                    try diag.print("Missing required argument '--{s}'", .{kebabFromSnake(f.name)});
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

    var field_names: [info.fields.len][]const u8 = undefined;
    var field_types: [info.fields.len]type = undefined;
    var field_attrs: [info.fields.len]std.builtin.Type.StructField.Attributes = undefined;

    inline for (info.fields, 0..) |f, i| {
        const required = if (f.defaultValue()) |def|
            def.required
        else
            false;

        field_names[i] = f.name;
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
