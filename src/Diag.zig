const std = @import("std");

msg: [MAXLEN]u8,
len: usize,

const Self = @This();
const MAXLEN: usize = 2048;
pub const empty: Self = .{ .msg = undefined, .len = 0 };

pub fn print(self: *Self, comptime fmt: []const u8, args: anytype) std.Io.Writer.Error!void {
    var writer = std.Io.Writer.fixed(&self.msg);
    try writer.print(fmt, args);
    self.len = writer.end;
}

pub fn report(self: *const Self) []const u8 {
    return self.msg[0..self.len];
}

pub fn reportToFile(self: *const Self, io: std.Io, file: std.Io.File) std.Io.Writer.Error!void {
    var writer = file.writer(io, &.{});
    try writer.interface.writeAll(self.report());
}
