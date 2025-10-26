const std = @import("std");
const Allocator = std.mem.Allocator;

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

    pub const ToSource = union(enum) {
        long: []const u8,
        short: u8,
    };

    pub fn getTextEx(self: Span, source: []const u8) ToSource {
        if (self.end - self.start == 1) {
            return .{ .short = source[self.start] };
        }
        return .{ .long = source[self.start..self.end] };
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

/// Creates an iterator from an array of slices
pub const SliceIterator = struct {
    items: []const []const u8,
    index: usize,

    const Self = @This();

    pub fn init(items: []const []const u8) Self {
        return .{ .items = items, .index = 0 };
    }

    /// **Warning**: doesn't work properly if there is a string with escaped quotes for an argument's value
    pub fn fromString(allocator: Allocator, string: []const u8) std.mem.Allocator.Error!Self {
        var it = std.mem.splitScalar(u8, string, ' ');
        var items: std.ArrayList([]const u8) = .empty;

        while (it.next()) |item| {
            try items.append(allocator, item);
        }

        return .{ .items = try items.toOwnedSlice(allocator), .index = 0 };
    }

    /// Call only if initialized with `fromString`
    pub fn deinit(self: *Self, allocator: Allocator) void {
        allocator.free(self.items);
    }

    pub fn next(self: *Self) ?[]const u8 {
        if (self.index == self.items.len) return null;

        defer self.index += 1;
        return self.items[self.index];
    }
};
