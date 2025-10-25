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

pub const Args = struct {
    // arg1: Arg(bool) = .{},
    arg1: Arg(i64) = .{},
    arg2: Arg(3) = .{},
    arg3: Arg(f64),
    // arg4: Arg([]const u8) = .{},
};

// const Args = struct {
//     arg1: Arg(bool),
//     arg2: Arg(i64),
//     arg3: Arg(f64),
//     arg4: Arg([]const u8),
//     arg5: Arg(Size),
// };

pub fn main() !void {
    try clarg.printHelp(Args);

    var dbga = std.heap.DebugAllocator(.{}){};
    const gpa = dbga.allocator();
    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();

    const parsed = try clarg.parse(Args, &args);
    _ = parsed; // autofix
}
