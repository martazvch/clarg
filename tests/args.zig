const Arg = @import("clarg").Arg;

pub const TypeOnlyArgs = struct {
    arg1: Arg(bool) = .{},
    arg2: Arg(i64) = .{},
    arg3: Arg(f64) = .{},
    arg4: Arg([]const u8) = .{},
};
