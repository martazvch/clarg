const std = @import("std");
const allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEql = std.testing.expectEqual;
const eql = std.mem.eql;
const clarg = @import("clarg");
const Arg = clarg.Arg;
const Diag = clarg.Diag;
const SliceIter = clarg.SliceIter;

// Test common data
const Size = enum { small, medium, large };

fn clargTest(Args: type, cli_args: []const u8, err_msg: []const u8) !void {
    var iter = try SliceIter.fromString(allocator, cli_args);
    defer iter.deinit(allocator);
    var diag: Diag = .empty;
    _ = clarg.parse("", Args, &iter, &diag, .{ .skip_first = false }) catch {
        try expect(eql(u8, err_msg, diag.report()));
    };
}

test "value args" {
    const Args = struct {
        arg1: Arg(bool),
        arg2: Arg(4) = .{ .short = 'i' },
        arg3: Arg(65.12),
        arg4: Arg("/home"),
        arg5: Arg(Size.large),
    };

    try clargTest(Args, "--arg6", "Unknown argument 'arg6'");
    try clargTest(Args, "--arg2=6 --arg2=65", "Already parsed argument 'arg2' (or its long/short version)");
    try clargTest(Args, "--arg2=5 -i=9", "Already parsed argument 'i' (or its long/short version)");
    try clargTest(Args, "--arg4=true", "Expect a value of type 'string' for argument 'arg4'");
}
