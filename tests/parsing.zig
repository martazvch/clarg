const std = @import("std");
const allocator = std.testing.allocator;
const expect = std.testing.expect;
const clarg = @import("clarg");
const Arg = clarg.Arg;
const Diag = clarg.Diag;
const SliceIter = clarg.SliceIter;

pub const Size = enum { small, medium, large };

test "type args" {
    const Args = struct {
        arg1: Arg(bool),
        arg2: Arg(i64),
        arg3: Arg(f64),
        arg4: Arg([]const u8),
        arg5: Arg(.string),
        arg6: Arg(Size),
    };

    {
        var iter = try SliceIter.fromString(allocator, "");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse("prog", Args, &iter, &diag, .{ .skip_first = false });

        try expect(!parsed.arg1);
        try expect(parsed.arg2 == null);
        try expect(parsed.arg3 == null);
        try expect(parsed.arg4 == null);
        try expect(parsed.arg5 == null);
        try expect(parsed.arg6 == null);
    }
    {
        var iter = try SliceIter.fromString(allocator, "--arg1 --arg2=4 --arg6=medium --arg4=config.txt --arg3=56.7 --arg5=release");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse("prog", Args, &iter, &diag, .{ .skip_first = false });

        try expect(parsed.arg1);
        try expect(parsed.arg2.? == 4);
        try expect(parsed.arg3.? == 56.7);
        try expect(std.mem.eql(u8, parsed.arg4.?, "config.txt"));
        try expect(std.mem.eql(u8, parsed.arg5.?, "release"));
        try expect(parsed.arg6.? == .medium);
    }
}

test "value args" {
    const Args = struct {
        arg1: Arg(bool),
        arg2: Arg(4),
        arg3: Arg(65.12),
        arg4: Arg("/home"),
        arg5: Arg(Size.large),
    };

    {
        var iter = try SliceIter.fromString(allocator, "");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse("prog", Args, &iter, &diag, .{ .skip_first = false });

        try expect(parsed.arg1 == false);
        try expect(parsed.arg2 == 4);
        try expect(parsed.arg3 == 65.12);
        try expect(std.mem.eql(u8, parsed.arg4, "/home"));
        try expect(parsed.arg5 == .large);
    }
    {
        var iter = try SliceIter.fromString(allocator, "--arg1 --arg2=4 --arg5=medium --arg4=config.txt --arg3=56.7");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse("prog", Args, &iter, &diag, .{ .skip_first = false });

        try expect(parsed.arg1);
        try expect(parsed.arg2 == 4);
        try expect(parsed.arg3 == 56.7);
        try expect(std.mem.eql(u8, parsed.arg4, "config.txt"));
        try expect(parsed.arg5 == .medium);
    }
}

test "with default value" {
    const Args = struct {
        arg1: Arg(bool) = .{},
        arg2: Arg(4) = .{},
        arg3: Arg(65.12) = .{},
        arg4: Arg("/home") = .{},
        arg5: Arg(Size.large) = .{},
    };

    {
        var iter = try SliceIter.fromString(allocator, "");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse("prog", Args, &iter, &diag, .{ .skip_first = false });

        try expect(parsed.arg1 == false);
        try expect(parsed.arg2 == 4);
        try expect(parsed.arg3 == 65.12);
        try expect(std.mem.eql(u8, parsed.arg4, "/home"));
        try expect(parsed.arg5 == .large);
    }
    {
        var iter = try SliceIter.fromString(allocator, "--arg1 --arg2=4 --arg5=medium --arg4=config.txt --arg3=56.7");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse("prog", Args, &iter, &diag, .{ .skip_first = false });

        try expect(parsed.arg1);
        try expect(parsed.arg2 == 4);
        try expect(parsed.arg3 == 56.7);
        try expect(std.mem.eql(u8, parsed.arg4, "config.txt"));
        try expect(parsed.arg5 == .medium);
    }
}

test "short" {
    const Args = struct {
        arg1: Arg(bool) = .{ .short = 'a' },
        arg2: Arg(4) = .{},
        arg3: Arg(65.12) = .{ .short = 'f' },
        arg4: Arg("/home") = .{ .short = 'g' },
        arg5: Arg(Size.large) = .{ .short = 't' },
    };

    {
        var iter = try SliceIter.fromString(allocator, "-t=small -a -f=98.24 -g=file.txt");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse("prog", Args, &iter, &diag, .{ .skip_first = false });

        try expect(parsed.arg1);
        try expect(parsed.arg2 == 4);
        try expect(parsed.arg3 == 98.24);
        try expect(std.mem.eql(u8, parsed.arg4, "file.txt"));
        try expect(parsed.arg5 == .small);
    }
}

test "positional" {
    const Args = struct {
        arg1: Arg(bool),
        arg2: Arg(4),
        arg3: Arg(65.12) = .{ .positional = true },
        arg4: Arg("/home") = .{ .short = 'g' },
        arg5: Arg(Size.large) = .{ .short = 'a', .positional = true },
    };

    {
        var iter = try SliceIter.fromString(allocator, "998.123 -arg2=34 --arg1 medium -g=alright");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse("prog", Args, &iter, &diag, .{ .skip_first = false });

        try expect(parsed.arg1);
        try expect(parsed.arg2 == 34);
        try expect(parsed.arg3 == 998.123);
        try expect(std.mem.eql(u8, parsed.arg4, "alright"));
        try expect(parsed.arg5 == .medium);
    }
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

    const CmdArgs = struct {
        arg: Arg(5),
        size: Arg(Size.large) = .{ .desc = "matter of taste", .short = 's' },
        cmd: Arg(OpCmdArgs) = .{ .desc = "operates on data" },
        cmd_compile: Arg(CompileCmd),
        help: Arg(bool) = .{ .short = 'h' },
    };

    {
        // We pass the arg as --it_count because clarg is gonna try to modify it but I feel that
        // @constCast() an comptime string like this one is the cause of the Bus error.
        // I don't know how to test it without this hack. Works properly when tried in real.
        var iter = try SliceIter.fromString(allocator, "cmd -o=mul --it_count=75");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse("prog", CmdArgs, &iter, &diag, .{ .skip_first = false });

        try expect(parsed.arg == 5);
        try expect(parsed.size == .large);
        try expect(parsed.cmd != null);
        try expect(parsed.cmd_compile == null);
        try expect(!parsed.help);

        const cmd = parsed.cmd orelse unreachable;
        try expect(cmd.it_count == 75);
        try expect(cmd.op == .mul);
    }

    {
        // We pass the cmd as cmd_compile for the same reason as above
        var iter = try SliceIter.fromString(allocator, "cmd_compile -p=myplace --print_ir");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse("prog", CmdArgs, &iter, &diag, .{ .skip_first = false });

        try expect(parsed.arg == 5);
        try expect(parsed.size == .large);
        try expect(parsed.cmd == null);
        try expect(parsed.cmd_compile != null);
        try expect(!parsed.help);

        const cmd = parsed.cmd_compile orelse unreachable;
        try expect(cmd.print_ir);
        try expect(std.mem.eql(u8, cmd.dir_path, "myplace"));
    }
}
