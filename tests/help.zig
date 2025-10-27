const std = @import("std");
const allocator = std.testing.allocator;
const clarg = @import("clarg");
const Arg = clarg.Arg;
const Diag = clarg.Diag;
const SliceIter = clarg.SliceIter;

const NoColor = "\x1b[0m";
const Red = "\x1b[31m";

const Error = std.Io.Writer.Error || error{TestExpectedEqual};

pub const Size = enum { small, medium, large };

fn genHelp(Args: type, writer: *std.Io.Writer, prog_name: []const u8) !void {
    var iter = try SliceIter.fromString(allocator, "");
    defer iter.deinit(allocator);
    var diag: Diag = .empty;
    _ = clarg.parse(prog_name, Args, &iter, &diag, .{ .skip_first = false }) catch {};
    try clarg.help(Args, writer);
}

test "type only" {
    const Args = struct {
        arg1: Arg(bool) = .{ .desc = "First argument" },
        arg2: Arg(i64) = .{},
        arg3: Arg(f64) = .{ .desc = "Third argument, this one is a string", .short = 's' },
        arg4: Arg([]const u8) = .{},
        arg5: Arg(Size) = .{ .desc = "Choose the size you want", .short = 'p' },
    };

    var wa = std.Io.Writer.Allocating.init(allocator);
    defer wa.deinit();
    try genHelp(Args, &wa.writer, "prog1");

    try clargTest(
        @src().fn_name,
        wa.writer.buffered(),
        \\Usage:
        \\  prog1 [options] [args]
        \\
        \\Options:
        \\  --arg1              First argument
        \\  --arg2 <int>
        \\  -s, --arg3 <float>  Third argument, this one is a string
        \\  --arg4 <string>
        \\  -p, --arg5 <enum>   Choose the size you want
        \\                        Supported values:
        \\                          small
        \\                          medium
        \\                          large
        \\
        ,
    );
}

test "default value" {
    const Args = struct {
        arg1: Arg(123) = .{ .desc = "Still the first argument" },
        arg2: Arg(45.8) = .{ .desc = "Gimme a float", .short = 'f' },
        arg3: Arg("/home") = .{ .desc = "Bring me home" },
        arg4: Arg(Size.large) = .{ .desc = "Matter of taste", .short = 's' },
    };

    var wa = std.Io.Writer.Allocating.init(allocator);
    defer wa.deinit();
    try genHelp(Args, &wa.writer, "prog2");

    try clargTest(
        @src().fn_name,
        wa.writer.buffered(),
        \\Usage:
        \\  prog2 [options] [args]
        \\
        \\Options:
        \\  --arg1 <int>        Still the first argument [default: 123]
        \\  -f, --arg2 <float>  Gimme a float [default: 45.8]
        \\  --arg3 <string>     Bring me home [default: "/home"]
        \\  -s, --arg4 <enum>   Matter of taste [default: large]
        \\                        Supported values:
        \\                          small
        \\                          medium
        \\                          large
        \\
        ,
    );
}

test "clarg enum literal" {
    const Args = struct {
        arg1: Arg(.string) = .{ .desc = "Can use this enum literal" },
    };

    var wa = std.Io.Writer.Allocating.init(allocator);
    defer wa.deinit();
    try genHelp(Args, &wa.writer, "prog3");

    try clargTest(
        @src().fn_name,
        wa.writer.buffered(),
        \\Usage:
        \\  prog3 [options] [args]
        \\
        \\Options:
        \\  --arg1 <string>  Can use this enum literal
        \\
        ,
    );
}

test "all categories" {
    const Args = struct {
        arg1: Arg(.string) = .{ .desc = "Can use this enum literal" },
        arg2: Arg("/home") = .{ .desc = "path", .positional = true },
        it_count: Arg(5) = .{ .desc = "iteration count", .short = 'i' },

        pub const description =
            \\This is a little program to parse useless data
            \\and then tries to render them in a nice way
        ;
    };

    var wa = std.Io.Writer.Allocating.init(allocator);
    defer wa.deinit();
    try genHelp(Args, &wa.writer, "data-visu");

    try clargTest(
        @src().fn_name,
        wa.writer.buffered(),
        \\Usage:
        \\  data-visu [options] [args]
        \\
        \\Description:
        \\  This is a little program to parse useless data
        \\  and then tries to render them in a nice way
        \\
        \\Arguments:
        \\  <string>              path [default: "/home"]
        \\
        \\Options:
        \\  --arg1 <string>       Can use this enum literal
        \\  -i, --it-count <int>  iteration count [default: 5]
        \\
        ,
    );
}

test "commands" {
    const Op = enum { add, sub, mul, div };
    const OpCmdArgs = struct {
        it_count: Arg(5) = .{ .desc = "iteration count", .short = 'i' },
        op: Arg(Op.add) = .{ .desc = "operation", .short = 'o' },
        help: Arg(bool) = .{ .short = 'h' },
    };

    const CompileCmd = struct {
        print_ir: Arg(bool) = .{ .desc = "prints IR" },
        dir_path: Arg("/home") = .{ .short = 'p' },
        help: Arg(bool) = .{ .short = 'h' },
    };

    const Args = struct {
        arg_arg: Arg(5),
        size: Arg(Size.large) = .{ .desc = "matter of taste", .short = 's' },
        cmd: Arg(OpCmdArgs) = .{ .desc = "operates on data" },
        cmd_compile: Arg(CompileCmd),
        help: Arg(bool) = .{ .short = 'h' },
    };

    {
        var wa = std.Io.Writer.Allocating.init(allocator);
        defer wa.deinit();
        try genHelp(Args, &wa.writer, "rover");

        try clargTest(
            @src().fn_name,
            wa.writer.buffered(),
            \\Usage:
            \\  rover [options] [args]
            \\  rover [commands] [options] [args]
            \\
            \\Commands:
            \\  cmd                operates on data
            \\  cmd-compile
            \\
            \\Options:
            \\  --arg-arg <int> [default: 5]
            \\  -s, --size <enum>  matter of taste [default: large]
            \\                       Supported values:
            \\                         small
            \\                         medium
            \\                         large
            \\  -h, --help
            \\
            ,
        );
    }
    {
        var wa = std.Io.Writer.Allocating.init(allocator);
        defer wa.deinit();
        try genHelp(OpCmdArgs, &wa.writer, "rover");

        try clargTest(
            @src().fn_name,
            wa.writer.buffered(),
            \\Usage:
            \\  rover [options] [args]
            \\
            \\Options:
            \\  -i, --it-count <int>  iteration count [default: 5]
            \\  -o, --op <enum>       operation [default: add]
            \\                          Supported values:
            \\                            add
            \\                            sub
            \\                            mul
            \\                            div
            \\  -h, --help
            \\
            ,
        );
    }

    {
        var wa = std.Io.Writer.Allocating.init(allocator);
        defer wa.deinit();
        // We pass the arg as cmd_compile because clarg is gonna try to modify it but I feel that
        // @constCast() an comptime string like this one is the cause of the Bus error.
        // I don't know how to test it without this hack. Works properly when tried in real.
        try genHelp(CompileCmd, &wa.writer, "rover");

        try clargTest(
            @src().fn_name,
            wa.writer.buffered(),
            \\Usage:
            \\  rover [options] [args]
            \\
            \\Options:
            \\  --print-ir               prints IR
            \\  -p, --dir-path <string> [default: "/home"]
            \\  -h, --help
            \\
            ,
        );
    }
}

fn clargTest(comptime fn_name: []const u8, got: []const u8, expect: []const u8) Error!void {
    if (!std.mem.eql(u8, expect, got)) return printErr(fn_name, got, expect);
}

fn printErr(comptime fn_name: []const u8, got: []const u8, expect: []const u8) Error {
    const long, const short = if (expect.len > got.len) .{ expect, got } else .{ got, expect };

    var err = false;
    var err_idx: usize = 0;

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
            try writer.writeAll(Red);
        }

        try writer.writeByte(l);
    }

    try writer.writeAll(NoColor);
    const underline = "-" ** (fn_name.len + 11);

    std.debug.print("Difference on char {}, expect '{c}' but got '{c}'\n", .{ err_idx, expect[err_idx], got[err_idx] });
    std.debug.print("Diff in '{s}':\n{s}\n{s}\n{s}", .{ fn_name, underline, writer.buffered(), underline });
    std.debug.print("\nGot:\n----\n{s}\n{s}\n", .{ got, underline });
    std.debug.print("\nExpect:\n----\n{s}\n{s}\n", .{ expect, underline });

    return error.TestExpectedEqual;
}
