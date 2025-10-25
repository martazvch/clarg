const std = @import("std");
const allocator = std.testing.allocator;
const expectEql = std.testing.expectEqual;
const clarg = @import("clarg");
const Arg = clarg.Arg;

// Test common data
const Size = enum { small, medium, large };

test "no default" {
    const Args = struct {
        arg1: Arg(bool),
        arg2: Arg(i64),
        arg3: Arg(f64),
        arg4: Arg([]const u8),
        arg5: Arg(Size),
    };

    const input = [_][]const u8{""};
    const parsed = try clarg.parse(Args, input);
    _ = parsed; // autofix
}
