const std = @import("std");
const Allocator = std.mem.Allocator;

/// Convert snake case to kind of kebab case with '--' at the beginning
pub fn kebabFromSnakeDash(comptime text: []const u8) []const u8 {
    comptime var name: []const u8 = "--";

    inline for (text) |c| {
        name = name ++ if (c == '_') "-" else .{c};
    }

    return name;
}

/// Convert snake case to kebab case
pub fn kebabFromSnake(comptime text: []const u8) []const u8 {
    comptime var name: []const u8 = "";

    inline for (text) |c| {
        name = name ++ if (c == '_') "-" else .{c};
    }

    return name;
}

/// Convert kebab case to snake case
pub fn snakeFromKebab(text: []u8) void {
    for (text) |*c| {
        if (c.* == '-') c.* = '_';
    }
}
