const std = @import("std");
const allocator = std.testing.allocator;
const expect = std.testing.expect;
const expectEql = std.testing.expectEqual;
const clarg = @import("clarg");
const Arg = clarg.Arg;
const Diag = clarg.Diag;
const SliceIter = clarg.SliceIter;

// Test common data
const Size = enum { small, medium, large };

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
        const parsed = try clarg.parse(Args, &iter, &diag);

        try expect(!parsed.arg1);
        try expect(parsed.arg2 == null);
        try expect(parsed.arg3 == null);
        try expect(parsed.arg4 == null);
        try expect(parsed.arg5 == null);
        try expect(parsed.arg6 == null);
    }
    {
        var iter = try SliceIter.fromString(allocator, "prog --arg1 --arg2=4 --arg6=medium --arg4=config.txt --arg3=56.7 --arg5=release");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &iter, &diag);

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
        const parsed = try clarg.parse(Args, &iter, &diag);

        try expect(parsed.arg1 == false);
        try expect(parsed.arg2 == 4);
        try expect(parsed.arg3 == 65.12);
        try expect(std.mem.eql(u8, parsed.arg4, "/home"));
        try expect(parsed.arg5 == .large);
    }
    {
        var iter = try SliceIter.fromString(allocator, "prog --arg1 --arg2=4 --arg5=medium --arg4=config.txt --arg3=56.7");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &iter, &diag);

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
        const parsed = try clarg.parse(Args, &iter, &diag);

        try expect(parsed.arg1 == false);
        try expect(parsed.arg2 == 4);
        try expect(parsed.arg3 == 65.12);
        try expect(std.mem.eql(u8, parsed.arg4, "/home"));
        try expect(parsed.arg5 == .large);
    }
    {
        var iter = try SliceIter.fromString(allocator, "prog --arg1 --arg2=4 --arg5=medium --arg4=config.txt --arg3=56.7");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &iter, &diag);

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
        var iter = try SliceIter.fromString(allocator, "prog -t=small -a -f=98.24 -g=file.txt");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &iter, &diag);

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
        var iter = try SliceIter.fromString(allocator, "prog 998.123 -arg2=34 --arg1 medium -g=alright");
        defer iter.deinit(allocator);
        var diag: Diag = .empty;
        const parsed = try clarg.parse(Args, &iter, &diag);

        try expect(parsed.arg1);
        try expect(parsed.arg2 == 34);
        try expect(parsed.arg3 == 998.123);
        try expect(std.mem.eql(u8, parsed.arg4, "alright"));
        try expect(parsed.arg5 == .medium);
    }
}
