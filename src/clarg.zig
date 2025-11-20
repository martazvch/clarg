const std = @import("std");
const Type = std.builtin.Type;
const Writer = std.Io.Writer;

const Proto = @import("proto.zig").Proto;
const ProtoErr = @import("proto.zig").Error;
const utils = @import("utils.zig");
const Span = utils.Span;
const kebabFromSnake = utils.kebabFromSnake;

const arg = @import("arg.zig");
const Diag = @import("Diag.zig");

args: []const [:0]const u8,
current: usize,

const Self = @This();

const Error = error{
    AlreadyParsed,
    ExpectValue,
    WrongValueType,
    UnknownArg,
    NamedPositional,
    InvalidArg,
};

pub const AllErrors = std.Io.Writer.Error || Error || ProtoErr;

pub var prog: []const u8 = "";

/// Parsing configuration
pub const Config = struct {
    /// Assignment operator (token between name and value)
    op: Op = .equal,

    pub const Op = enum {
        equal,
        colon,
        space,

        pub fn eq(self: Op, char: u8) bool {
            return switch (self) {
                .equal => char == '=',
                .colon => char == ':',
                .space => char == ' ',
            };
        }
    };
};

pub fn parse(Args: type, args: []const [:0]const u8, diag: *Diag, config: Config) AllErrors!arg.ParsedArgs(Args) {
    prog = args[0];
    var parser: Self = .{ .args = args[1..], .current = 0 };
    return parser.parseCmd(Args, diag, config);
}

fn at(self: *const Self) []const u8 {
    return self.args[self.current];
}

fn prev(self: *const Self) []const u8 {
    return self.args[self.current - 1];
}

fn advance(self: *Self) []u8 {
    self.current += 1;
    return @constCast(self.args[self.current - 1]);
}

fn parseCmd(self: *Self, Args: type, diag: *Diag, config: Config) AllErrors!arg.ParsedArgs(Args) {
    if (@typeInfo(Args) != .@"struct") {
        @compileError("Arguments type must be a structure");
    }
    const ParsedArgs = arg.ParsedArgs(Args);

    var options_started = false;
    var parsed_positional: usize = 0;
    var res = ParsedArgs{};
    var proto: Proto(arg.ArgsWithHelp(Args)) = .{};
    const infos = @typeInfo(arg.ArgsWithHelp(Args)).@"struct";

    cmd: {
        arg: while (self.current < self.args.len) {
            const arg_parsed = self.getNameAndValueRanges(config.op) catch |err| {
                try diag.print("Invalid argument '{s}'", .{self.prev()});
                return err;
            };
            const name = arg_parsed.name;
            const full_name = arg_parsed.full_name;

            if (!options_started and arg_parsed.is_cmd) {
                inline for (infos.fields) |field| {
                    if (comptime arg.is(field, .cmd)) {
                        if (std.mem.eql(u8, field.name, name)) {
                            @field(res, field.name) = try self.parseCmd(field.type.Declared, diag, config);
                            break :cmd;
                        }
                    }
                }
            }

            options_started = true;

            inline for (infos.fields) |field| {
                if (matchField(field, name, arg_parsed.is_short)) {
                    if (@field(proto.fields, field.name).done) {
                        try diag.print("Already parsed argument '{s}' (or its long/short version)", .{full_name});
                        return error.AlreadyParsed;
                    } else {
                        // Check if it's a positional, can't use them by their name
                        if (field.defaultValue()) |def| if (def.positional) {
                            try diag.print("Can't use '{s}' by it's name as it's a positional argument", .{full_name});
                            return error.NamedPositional;
                        };

                        if (arg_parsed.value) |value| {
                            @field(res, field.name) = argValue(field.type.Value, value) catch {
                                try diag.print("Expect a value of type '{s}' for argument '{s}'", .{ arg.typeStr(field), full_name });
                                return error.WrongValueType;
                            };
                        }
                        // If it's a boolean flag, no value needed
                        else if (field.type.Value == bool) {
                            @field(res, field.name) = true;
                        }
                        // If the value was needed
                        else if (arg.needsValue(field)) {
                            try diag.print("Expect a value of type '{s}' for argument '{s}'", .{ arg.typeStr(field), full_name });
                            return error.ExpectValue;
                        }

                        @field(proto.fields, field.name).done = true;
                        continue :arg;
                    }
                }
            }

            // Positional
            var count: usize = 0;

            inline for (infos.fields) |field| {
                if (field.defaultValue()) |def| {
                    if (def.positional) {
                        if (count == parsed_positional) {
                            @field(res, field.name) = argValue(@field(field.type, "Value"), name) catch {
                                try diag.print("Expect a value of type '{s}' for positional argument '--{s}'", .{ arg.typeStr(field), kebabFromSnake(field.name) });
                                return error.WrongValueType;
                            };

                            parsed_positional += 1;
                            @field(proto.fields, field.name).done = true;
                            continue :arg;
                        }

                        count += 1;
                    }
                }
            }

            try diag.print("Unknown argument '{s}'", .{full_name});
            return error.UnknownArg;
        }

        // We check only if help wasn't asked
        if (!@field(proto.fields, "help").done) {
            try proto.validate(diag);
        }
    }

    return res;
}

fn matchField(field: Type.StructField, arg_name: []const u8, short: bool) bool {
    if (short) {
        return matchFieldShort(field, arg_name[0]);
    }

    return std.mem.eql(u8, field.name, arg_name);
}

fn matchFieldShort(field: Type.StructField, arg_name: u8) bool {
    if (field.defaultValue()) |def| {
        if (def.short) |short| {
            return short == arg_name;
        }
    }

    return false;
}

fn argValue(T: type, value: []const u8) error{TypeMismatch}!T {
    return switch (T) {
        i64 => std.fmt.parseInt(i64, value, 10) catch error.TypeMismatch,
        f64 => std.fmt.parseFloat(f64, value) catch error.TypeMismatch,
        []const u8 => value,
        else => switch (@typeInfo(T)) {
            .@"enum" => return std.meta.stringToEnum(T, value) orelse error.TypeMismatch,
            else => @panic("Unsupported value type: " ++ @typeName(T)),
        },
    };
}

const ParsedArgRes = struct {
    name: []const u8,
    full_name: []const u8,
    value: ?[]const u8,
    is_short: bool,
    is_cmd: bool,
};

/// Modifies inplace the text to avoid allocation
fn getNameAndValueRanges(self: *Self, op: Config.Op) Error!ParsedArgRes {
    const State = enum { start, name, value };

    var dashes: usize = 0;
    var current: usize = 0;
    var full_name: []const u8 = undefined;
    var name: []const u8 = undefined;
    var name_start: usize = 0;
    var value: ?[]const u8 = null;

    var text = self.advance();

    s: switch (State.start) {
        .start => {
            // If we reached end of argument but still in start, it's an invalid arg
            if (current == text.len) {
                return error.InvalidArg;
            }

            if (text[current] != '-') {
                name_start = current;
                continue :s .name;
            }

            dashes += 1;
            current += 1;
            continue :s .start;
        },
        .name => {
            name = text[name_start..current];
            full_name = text[0..current];

            if (current == text.len) {
                if (op == .space and self.current < self.args.len) {
                    // If next starts with '-', it's an argument, not a value
                    if (self.at()[0] == '-') {
                        break :s;
                    }

                    current = 0;
                    text = self.advance();
                    continue :s .value;
                }

                break :s;
            }

            if (text[current] == '-') text[current] = '_';

            if (op.eq(text[current])) {
                current += 1;
                continue :s .value;
            }

            current += 1;
            continue :s .name;
        },
        .value => value = text[current..text.len],
    }

    return .{
        .name = name,
        .full_name = full_name,
        .value = value,
        .is_short = dashes == 1,
        .is_cmd = text[0] != '-',
    };
}
