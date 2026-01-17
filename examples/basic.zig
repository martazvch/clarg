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
    // ---------------
    // Default values
    //   You can provide a default value for each argument or leave it uninit
    // No default value
    print_ast: Arg(bool),
    // Using default value:
    //   .desc = ""
    //   .short = null,
    //   .positional = false
    //   .required = false
    print_code: Arg(bool) = .{},
    // Using default with custom values
    print_ir: Arg(bool) = .{ .desc = "Print IR", .short = 'p', .required = true, .positional = false },

    // ------
    // Types
    //   You can specify the following types for arguments
    //   As no default value are specified, the resulting type when parsed will
    //   be ?T where T is the type inside `Arg(T)`
    t0: Arg(bool),
    t1: Arg(i64),
    t2: Arg(f64),
    t3: Arg([]const u8),
    // For strings there is also the enum literal .string that is supported
    t4: Arg(.string),
    // Enums
    t5: Arg(Size),

    // --------------
    // Default value
    //   You can use a value instead of a type to provide a fallback value
    //   Argument's type will be infered and the resulting type when parsed will
    //   be T where T is the type inside `Arg(T)`
    // Interger
    count: Arg(5) = .{ .desc = "iteration count", .short = 'c' },
    // Float
    delta: Arg(10.5) = .{ .desc = "delta time between calculations", .short = 'd', .required = true },
    // String
    dir_path: Arg("/home") = .{ .desc = "file path", .short = 'f' },
    // Enum
    other_size: Arg(Size.small) = .{ .desc = "size of binary" },

    // ------------
    // Positionals
    //   Positional arguments are defined using the `.positional` field and are parsed
    //   in the order of declaration. They can be define before and after other arguments
    file: Arg(.string) = .{ .positional = true },
    outdir: Arg("/tmp") = .{ .positional = true },

    // -------------
    // Sub-commands
    //   They are simply defined by giving a structure as argument's type
    cmd: Arg(OpCmdArgs) = .{ .desc = "operates on input" },

    // Description will be displayed
    pub const description =
        \\Description of the program
        \\it can be anything
    ;
};

pub fn main(init: std.process.Init) !void {
    var diag: clarg.Diag = .empty;
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    const config: clarg.Config = .{
        .op = .space,
    };

    const parsed = clarg.parse(Args, args, &diag, config) catch {
        try diag.reportToFile(init.io, .stderr());
        std.process.exit(1);
    };

    if (parsed.help) {
        try clarg.helpToFile(Args, init.io, .stderr());
        return;
    }

    // No default value are optionals except bool that are false
    if (parsed.print_ast) {
        std.log.debug("Prints the AST", .{});
    }
    if (parsed.t4) |val| {
        std.log.debug("T4 value: {s}", .{val});
    }

    // Required arguments aren't optional
    std.log.debug("Delta: {}", .{parsed.delta});

    // Default values are usable as is
    std.log.debug("count: {d}", .{parsed.count});
    std.log.debug("outdir: {s}", .{parsed.outdir});

    // Sub command usage
    if (parsed.cmd) |cmd| {
        if (cmd.help) {
            try clarg.helpToFile(OpCmdArgs, init.io, .stderr());
        }
    }
}
