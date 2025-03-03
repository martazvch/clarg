const std = @import("std");
const clarg = @import("clarg");
const Arg = clarg.Arg;

const Size = enum { small, medium, big };

const Args = struct {
    print_ast: Arg(bool) = .{ .desc = "prints AST" },
    // file_path: Arg(.string) = .{ .desc = "file path", .short = "f" },
    count: Arg(5) = .{ .desc = "iteration count", .short = "c" },
    // size: Arg(Size) = .{ .desc = "size of binary" },
};

// TODO:
// enum default with: Size.small for example
// default string value: Arg("../main")
// Pos for positional argument?
pub fn main() !void {
    // const args = Args{};
    // @compileLog(args);

    try clarg.print_help(Args);
}
