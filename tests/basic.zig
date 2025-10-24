const std = @import("std");
const allocator = std.testing.allocator;
const expectEql = std.testing.expectEqual;
const clarg = @import("clarg");

const NoColor = "\x1b[0m";
const Red = "\x1b[31m";

const Error = std.Io.Writer.Error || error{TestExpectedEqual};

fn clargTest(comptime fn_name: []const u8, got: []const u8, expect: []const u8) Error!void {
    if (!std.mem.eql(u8, expect, got)) return printErr(fn_name, got, expect);
}

fn printErr(comptime fn_name: []const u8, got: []const u8, expect: []const u8) Error {
    const long, const short = if (expect.len > got.len) .{ expect, got } else .{ got, expect };

    var err = false;
    var err_idx: usize = 0;
    var err_exp: u8 = ' ';
    var err_got: u8 = ' ';

    var wa = std.Io.Writer.Allocating.init(allocator);
    defer wa.deinit();
    const writer = &wa.writer;

    for (long, 0..) |l, i| {
        if (i >= short.len) {
            try writer.writeByte(l);
            continue;
        }

        const s = short[i];
        if (l == s) {
            try writer.writeByte(l);
            continue;
        }

        if (!err) {
            err = true;
            err_idx = i;
            err_exp = expect[i];
            err_got = got[i];
            try writer.writeAll(Red);
        }

        try writer.writeByte(l);
    }

    try writer.writeAll(NoColor);
    const underline = "-" ** (fn_name.len + 11);

    std.debug.print("Difference on char {}, expect '{c}' but got '{c}'\n", .{ err_idx, err_exp, err_got });
    std.debug.print("Diff in '{s}':\n{s}\n{s}\n{s}", .{ fn_name, underline, writer.buffered(), underline });
    std.debug.print("\nGot:\n----\n{s}\n{s}\n", .{ got, underline });

    return error.TestExpectedEqual;
}

test "type only" {
    const Args = @import("args.zig").TypeOnlyArgs;

    var wa = std.Io.Writer.Allocating.init(allocator);
    defer wa.deinit();
    const writer = &wa.writer;

    try clarg.printHelpToStream(Args, writer);

    try clargTest(
        @src().fn_name,
        writer.buffered(),
        \\Options:
        \\  --arg1
        \\  --arg2 <int>
        \\  --arg3 <float>
        \\  --arg4 <string>
        \\  -h, --help       prints help
        ,
    );
}
