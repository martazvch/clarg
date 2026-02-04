const std = @import("std");
const allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEql = std.testing.expectEqual;
const eql = std.mem.eql;
const clarg = @import("clarg");
const Arg = clarg.Arg;
const Diag = clarg.Diag;
const Config = clarg.Config;
const SliceIter = clarg.SliceIter;

// Test common data
const Size = enum { small, medium, large };

fn clargTest(Args: type, comptime config: Config, args: []const [:0]const u8, err_msg: []const u8) !void {
    var diag: Diag = .empty;

    if (clarg.parse(Args, args, &diag, config)) |_| {
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
        arg_1: Arg(bool),
        arg2: Arg(4) = .{ .short = 'i' },
        arg_3: Arg(65.12),
        arg4: Arg("/home"),
        arg5: Arg(Size.large),
    };

    try clargTest(Args, .{}, &.{ "ray", "--arg0" }, "Unknown argument '--arg0'");
    try clargTest(Args, .{}, &.{ "ray", "--arg2=6", "--arg2=65" }, "Already parsed argument '--arg2' (or its long/short version)");
    try clargTest(Args, .{}, &.{ "ray", "--arg2=5", "-i=9" }, "Already parsed argument '-i' (or its long/short version)");
    try clargTest(Args, .{}, &.{ "ray", "--arg-3=true" }, "Expect a value of type '<float>' for argument '--arg-3'");
}

test "missing required" {
    const Args = struct {
        arg1: Arg(bool) = .{ .required = false },
        arg2: Arg(6) = .{ .required = true },
    };
    try clargTest(Args, .{}, &.{ "data-visu", "--arg1" }, "Missing required argument '--arg2'");
}

test "named positional" {
    const Args = struct {
        arg1: Arg(i64) = .{ .positional = true, .required = true },
    };

    try clargTest(Args, .{}, &.{ "arx", "--arg1" }, "Can't use '--arg1' by it's name as it's a positional argument");
    try clargTest(Args, .{}, &.{ "arx", "65.2" }, "Expect a value of type '<int>' for positional argument '--arg1'");
}

test "invalid arg" {
    const Args = struct {};

    try clargTest(Args, .{}, &.{ "objdump", "-" }, "Invalid argument '-'");
    try clargTest(Args, .{}, &.{ "objdump", "------" }, "Invalid argument '------'");
}

test "arg too long" {
    const Args = struct {
        argument: Arg(i64),
        other_argument: Arg(bool) = .{ .positional = true },
    };

    try clargTest(
        Args,
        .{ .max_size = 4 },
        &.{ "length", "--argument=3" },
        \\Argument 'argument' size is too big, current max length is 4 but found 8
        \\You can increase the limit with 'max_size' configuration field
        ,
    );
    try clargTest(
        Args,
        .{ .max_size = 10 },
        &.{ "length", "other-argument" },
        \\Argument 'other-argument' size is too big, current max length is 10 but found 14
        \\You can increase the limit with 'max_size' configuration field
        ,
    );
}
