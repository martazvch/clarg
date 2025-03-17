const std = @import("std");
const clarg = @import("clarg");
const Arg = clarg.Arg;

const Size = enum { small, medium, big };

const Args = struct {
    print_ast: Arg(bool) = .{ .desc = "prints AST" },
    file_path: Arg(.string) = .{ .desc = "file path", .short = "f" },
    count: Arg(5) = .{ .desc = "iteration count", .short = "c" },
    size: Arg(Size) = .{ .desc = "size of binary" },
    other_size: Arg(Size.small) = .{ .desc = "size of binary" },
    very_long_name_to_print_to_see_what_happens: Arg(bool) = .{ .desc = "very long arg name" },

    pub const description =
        \\Description of the program
        \\it can be anything
    ;
};

pub fn main() !void {
    // const args = Args{};
    // @compileLog(args);

    try clarg.print_help(Args);

    var dbga = std.heap.DebugAllocator(.{}){};
    const gpa = dbga.allocator();
    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();

    const parsed = try clarg.parse(&args, Args);
    _ = parsed; // autofix

}
