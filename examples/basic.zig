const std = @import("std");
const clarg = @import("clarg");
const Arg = clarg.Arg;
const Cmd = clarg.Cmd;

const Size = enum { small, medium, large };

// const Args = struct {
//     print_ast: Arg(bool) = .{ .desc = "prints AST" },
//     file_path: Arg(.string) = .{ .desc = "file path", .short = 'f' },
//     dir_path: Arg("/home") = .{ .desc = "file path", .short = 'f' },
//     count: Arg(5) = .{ .desc = "iteration count", .short = 'c' },
//     size: Arg(Size) = .{ .desc = "size of binary" },
//     other_size: Arg(Size.small) = .{ .desc = "size of binary" },
//     very_long_name_to_print_to_see_what_happens: Arg(bool) = .{ .desc = "very long arg name" },
//
//     pub const description =
//         \\Description of the program
//         \\it can be anything
//     ;
// };
const Op = enum { add, sub, mul, div };
const OpCmdArgs = struct {
    it_count: Arg(5) = .{ .desc = "iteration count", .short = 'i' },
    op: Arg(Op.add) = .{ .desc = "operation", .short = 'o' },
    help: Arg(bool) = .{ .short = 'h' },
};

const CompileCmd = struct {
    print_ir: Arg(bool) = .{ .desc = "prints IR" },
    dir_path: Arg("/home"),
    help: Arg(bool) = .{ .short = 'h' },
};

const Args = struct {
    arg_arg: Arg(5),
    size: Arg(Size.large) = .{ .desc = "matter of taste", .short = 's' },
    cmd: Arg(OpCmdArgs) = .{ .desc = "operates on data" },
    cmd_compile: Arg(CompileCmd),
    help: Arg(bool) = .{ .short = 'h' },
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var diag: clarg.Diag = .empty;
    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    const parsed = clarg.parse("basic", Args, &args, &diag, .{}) catch {
        try diag.reportToFile(.stderr());
        std.process.exit(1);
    };

    if (parsed.help) {
        try clarg.helpToFile(Args, .stderr());
    }

    if (parsed.cmd) |cmd| {
        if (cmd.help) {
            try clarg.helpToFile(CompileCmd, .stderr());
        }
    }
}
