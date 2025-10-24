const std = @import("std");

/// Given a structure, generates another one with the same fields
/// with each one being `false`. Can be used as a prototype of the structure
/// to keep track of which field have been initialiazed
pub fn StructProto(T: type) type {
    if (@typeInfo(T) != .@"struct") {
        @compileError("StructProto can only be used on structure types");
    }

    const info = @typeInfo(T).@"struct";

    var fields: [info.fields.len]std.builtin.Type.StructField = undefined;

    inline for (info.fields, 0..) |f, i| {
        fields[i] = .{
            .name = f.name,
            .type = bool,
            .default_value_ptr = &false,
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

/// Start and end offset in a buffer
pub const Span = struct {
    start: usize = 0,
    end: usize = 0,

    pub fn getText(self: Span, source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

/// Convert snake case to kind of kebab case with '--' at the beginning
pub fn fromSnake(comptime text: []const u8) []const u8 {
    comptime var name: []const u8 = "--";

    inline for (text) |c| {
        name = name ++ if (c == '_') "-" else .{c};
    }

    return name;
}
