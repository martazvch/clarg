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

    if (clarg.parse("", Args, &iter, &diag, .{ .skip_first = false })) |_| {
        return error.TestExpectedError;
    } else |_| {
        expect(eql(u8, err_msg, diag.report())) catch |err| {
            std.debug.print("Expect:\n\t{s}\nGot:\n\t{s}\n\n", .{ err_msg, diag.report() });
            return err;
        };
    }
}

test "value args" {
    const Args = struct {
        arg1: Arg(bool),
        arg2: Arg(4) = .{ .short = 'i' },
        arg3: Arg(65.12),
        arg4: Arg("/home"),
        arg5: Arg(Size.large),
    };

    try clargTest(Args, "--arg0", "Unknown argument '--arg0'");
    try clargTest(Args, "--arg2=6 --arg2=65", "Already parsed argument '--arg2' (or its long/short version)");
    try clargTest(Args, "--arg2=5 -i=9", "Already parsed argument '-i' (or its long/short version)");
    try clargTest(Args, "--arg3=true", "Expect a value of type '<float>' for argument '--arg3'");
}

test "missing required" {
    const Args = struct {
        arg1: Arg(bool) = .{ .required = false },
        arg2: Arg(6) = .{ .required = true },
    };
    try clargTest(Args, "--arg1", "Missing required argument '--arg2'");
}

test "named positional" {
    const Args = struct {
        arg1: Arg(i64) = .{ .positional = true, .required = true },
    };

    try clargTest(Args, "--arg1", "Can't use '--arg1' by it's name as it's a positional argument");
    try clargTest(Args, "65.2", "Expect a value of type '<int>' for positional argument '--arg1'");
}

test "invalid arg" {
    const Args = struct {};

    try clargTest(Args, "-", "Invalid argument '-'");
    try clargTest(Args, "------", "Invalid argument '------'");
}
