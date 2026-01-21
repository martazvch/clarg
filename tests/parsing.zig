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
        const args = [_][:0]const u8{"prog"};
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{});

        try expect(!parsed.arg1);
        try expect(parsed.arg2 == null);
        try expect(parsed.arg3 == null);
        try expect(parsed.arg4 == null);
        try expect(parsed.arg5 == null);
        try expect(parsed.arg6 == null);
    }
    {
        const args = [_][:0]const u8{ "prog", "--arg1", "--arg2=4", "--arg6=medium", "--arg4=config.txt", "--arg3=56.7", "--arg5=release" };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{});

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
        const args = [_][:0]const u8{"prog"};
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{});

        try expect(parsed.arg1 == false);
        try expect(parsed.arg2 == 4);
        try expect(parsed.arg3 == 65.12);
        try expect(std.mem.eql(u8, parsed.arg4, "/home"));
        try expect(parsed.arg5 == .large);
    }
    {
        const args = [_][:0]const u8{ "prog", "--arg1", "--arg2=4", "--arg5=medium", "--arg4=config.txt", "--arg3=56.7" };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{});

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
        const args = [_][:0]const u8{"prog"};
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{});

        try expect(parsed.arg1 == false);
        try expect(parsed.arg2 == 4);
        try expect(parsed.arg3 == 65.12);
        try expect(std.mem.eql(u8, parsed.arg4, "/home"));
        try expect(parsed.arg5 == .large);
    }
    {
        const args = [_][:0]const u8{ "prog", "--arg1", "--arg2=4", "--arg5=medium", "--arg4=config.txt", "--arg3=56.7" };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{});

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
        const args = [_][:0]const u8{ "prog", "-t=small", "-a", "-f=98.24", "-g=file.txt" };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{});

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
        arg6: Arg(i64) = .{ .positional = true, .required = true },
    };

    {
        const args = [_][:0]const u8{ "prog", "998.123", "--arg2=34", "--arg1", "medium", "-g=alright", "98" };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{});

        try expect(parsed.arg1);
        try expect(parsed.arg2 == 34);
        try expect(parsed.arg3 == 998.123);
        try expect(std.mem.eql(u8, parsed.arg4, "alright"));
        try expect(parsed.arg5 == .medium);
        try expect(parsed.arg6 == 98);
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
        const heap_it_count = try heapAllocString("--it-count=75");
        defer allocator.free(heap_it_count);

        const args = [_][:0]const u8{ "prog", "cmd", "-o=mul", heap_it_count };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(CmdArgs, &args, &diag, .{});

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
        const heap_print_ir = try heapAllocString("print-ir");
        defer allocator.free(heap_print_ir);
        const heap_cmp_compile = try heapAllocString("cmd-compile");
        defer allocator.free(heap_cmp_compile);

        const args = [_][:0]const u8{ "prog", heap_cmp_compile, "-p=myplace", heap_print_ir };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(CmdArgs, &args, &diag, .{});

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

test "separators" {
    const Args = struct {
        arg1: Arg(bool),
        arg2: Arg(i64),
        arg3: Arg(f64),
        arg4: Arg([]const u8),
        arg5: Arg(.string),
        arg6: Arg(Size),
    };

    {
        const args = [_][:0]const u8{ "prog", "--arg1", "--arg2=4", "--arg6=medium", "--arg4=config.txt", "--arg3=56.7", "--arg5=release" };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{ .op = .equal });

        try expect(parsed.arg1);
        try expect(parsed.arg2.? == 4);
        try expect(parsed.arg3.? == 56.7);
        try expect(std.mem.eql(u8, parsed.arg4.?, "config.txt"));
        try expect(std.mem.eql(u8, parsed.arg5.?, "release"));
        try expect(parsed.arg6.? == .medium);
    }
    {
        const args = [_][:0]const u8{ "prog", "--arg1", "--arg2:4", "--arg6:medium", "--arg4:config.txt", "--arg3:56.7", "--arg5:release" };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{ .op = .colon });

        try expect(parsed.arg1);
        try expect(parsed.arg2.? == 4);
        try expect(parsed.arg3.? == 56.7);
        try expect(std.mem.eql(u8, parsed.arg4.?, "config.txt"));
        try expect(std.mem.eql(u8, parsed.arg5.?, "release"));
        try expect(parsed.arg6.? == .medium);
    }
    {
        const args = [_][:0]const u8{ "prog", "--arg1", "--arg2", "4", "--arg6", "medium", "--arg4", "config.txt", "--arg3", "56.7", "--arg5", "release" };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{ .op = .space });

        try expect(parsed.arg1);
        try expect(parsed.arg2.? == 4);
        try expect(parsed.arg3.? == 56.7);
        try expect(std.mem.eql(u8, parsed.arg4.?, "config.txt"));
        try expect(std.mem.eql(u8, parsed.arg5.?, "release"));
        try expect(parsed.arg6.? == .medium);
    }
}

test "required" {
    const Args = struct {
        arg1: Arg(i64) = .{ .required = true },
    };

    {
        const args = [_][:0]const u8{ "prog", "--arg1=4" };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{ .op = .equal });

        // No need to '.?' thanks to the 'required' flag
        try expect(parsed.arg1 == 4);
    }
}

test "positional with dashes" {
    const Args = struct {
        file: Arg(.string) = .{ .positional = true },
    };

    {
        const heap_file = try heapAllocString("file-path-with-dash.txt");
        defer allocator.free(heap_file);

        const args = [_][:0]const u8{ "prog", heap_file };
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &args, &diag, .{ .op = .equal });

        // No need to '.?' thanks to the 'required' flag
        try expect(std.mem.eql(u8, parsed.file.?, "file-path-with-dash.txt"));
    }
}

/// Heap allocate because args with dashes are mutated in place
fn heapAllocString(string: []const u8) ![:0]const u8 {
    const path = try allocator.allocSentinel(u8, string.len, 0);
    @memcpy(path, string);
    return path;
}
