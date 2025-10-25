const Arg = @import("clarg").Arg;

const Size = enum { small, medium, large };

pub const TypeOnlyArgs = struct {
    arg1: Arg(bool) = .{ .desc = "First argument" },
    arg2: Arg(i64) = .{},
    arg3: Arg(f64) = .{ .desc = "Third argument, this one is a string", .short = 's' },
    arg4: Arg([]const u8) = .{},
    arg5: Arg(Size) = .{ .desc = "Choose the size you want", .short = 'p' },
};

pub const DefValArgs = struct {
    arg1: Arg(123) = .{ .desc = "Still the first argument" },
    arg2: Arg(45.8) = .{ .desc = "Gimme a float", .short = 'f' },
    arg3: Arg("/home") = .{ .desc = "Bring me home" },
    arg4: Arg(Size.large) = .{ .desc = "Matter of taste", .short = 's' },
};

pub const ClargEnumLit = struct {
    arg1: Arg(.string) = .{ .desc = "Can use this enum literal" },
};
