const std = @import("std");
const Diag = @import("Diag.zig");

/// Given a structure, generates another one with the same fields
/// with each one being `false`. Can be used as a prototype of the structure
/// to keep track of which field have been initialiazed
pub const Error = std.Io.Writer.Error || error{err};

pub fn Proto(T: type) type {
    return struct {
        fields: ProtoFields(T) = .{},

        pub fn validate(self: *@This(), diag: *Diag) Error!void {
            const proto_info = @typeInfo(@TypeOf(self.fields)).@"struct";

            inline for (proto_info.fields) |f| {
                const field = @field(self.fields, f.name);

                if (!field.done and field.required) {
                    var kebab: [f.name.len]u8 = undefined;
                    inline for (f.name, 0..) |c, i| {
                        kebab[i] = if (c == '_') '-' else c;
                    }

                    try diag.print("Missing required argument '--{s}'", .{kebab});
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

    var fields: [info.fields.len]std.builtin.Type.StructField = undefined;

    inline for (info.fields, 0..) |f, i| {
        const required = if (f.defaultValue()) |def|
            def.required
        else
            false;

        fields[i] = .{
            .name = f.name,
            .type = ProtoField,
            .default_value_ptr = &ProtoField{ .done = false, .required = required },
            .is_comptime = false,
            .alignment = @alignOf(bool),
        };
    }

    return @Type(.{ .@"struct" = .{
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
        .layout = .auto,
    } });
}
