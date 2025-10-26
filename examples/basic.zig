const std = @import("std");
const clarg = @import("clarg");
const Arg = clarg.Arg;

const Size = enum { small, medium, big };

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

const Args = struct {
    arg1: Arg(123) = .{ .desc = "Still the first argument" },
    arg2: Arg(45.8) = .{ .desc = "Gimme a float", .short = 'f' },
    arg3: Arg("/home") = .{ .desc = "Bring me home", .positional = true },
    arg4: Arg(Size.big) = .{ .desc = "Matter of taste", .short = 's' },
    help: Arg(bool) = .{ .short = 'h' },

    pub const description =
        \\Description of the program
        \\it can be anything
    ;
};

// const Args = struct {
//     arg1: Arg(bool) = .{},
//     arg2: Arg(4) = .{ .short = 'i' },
//     arg3: Arg(4.5) = .{},
//     arg4: Arg("/home") = .{},
//     arg5: Arg(Size.small) = .{ .positional = true },
//     help: Arg(bool) = .{ .short = 'h' },
// };

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    var args = try std.process.argsWithAllocator(gpa.allocator());
    defer args.deinit();

    var diag: clarg.Diag = .empty;
    const parsed = clarg.parse(Args, &args, &diag) catch {
        try diag.reportToFile(.stderr());
        std.process.exit(1);
    };

    if (parsed.help) {
        try clarg.printHelp(Args);
    }
}
