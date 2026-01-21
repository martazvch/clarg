const std = @import("std");
const clarg = @import("clarg");
const Arg = clarg.Arg;
const Cmd = clarg.Cmd;

const Op = enum { add, sub, mul, div };
const OpCmdArgs = struct {
    it_count: Arg(5) = .{ .desc = "iteration count", .short = 'i' },
    op: Arg(Op.add) = .{ .desc = "operation", .short = 'o' },
    help: Arg(bool) = .{ .short = 'h' },
};

const Size = enum { small, medium, large };
const Args = struct {
    file: Arg(.string) = .{ .positional = true },
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var diag: clarg.Diag = .empty;
    const args = try std.process.argsAlloc(gpa.allocator());
    defer std.process.argsFree(gpa.allocator(), args);

    const config: clarg.Config = .{
        .op = .space,
    };

    const parsed = clarg.parse(Args, args, &diag, config) catch {
        try diag.reportToFile(.stderr());
        std.process.exit(1);
    };

    if (parsed.help) {
        try clarg.helpToFile(Args, .stderr());
        return;
    }

    if (parsed.file) |f| {
        std.log.debug("File: {s}", .{f});
    }

    // No default value are optionals except bool that are false
    // if (parsed.print_ast) {
    //     std.log.debug("Prints the AST", .{});
    // }
    // if (parsed.t4) |val| {
    //     std.log.debug("T4 value: {s}", .{val});
    // }
    //
    // // Required arguments aren't optional
    // std.log.debug("Delta: {}", .{parsed.delta});
    //
    // // Default values are usable as is
    // std.log.debug("count: {d}", .{parsed.count});
    // std.log.debug("outdir: {s}", .{parsed.outdir});
    //
    // // Sub command usage
    // if (parsed.cmd) |cmd| {
    //     if (cmd.help) {
    //         try clarg.helpToFile(OpCmdArgs, .stderr());
    //     }
    // }
}
