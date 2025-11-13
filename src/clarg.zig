const std = @import("std");
const Type = std.builtin.Type;
const Writer = std.Io.Writer;

const Proto = @import("proto.zig").Proto;
const ProtoErr = @import("proto.zig").Error;
const utils = @import("utils.zig");
const Span = utils.Span;
const kebabFromSnakeDash = utils.kebabFromSnakeDash;
const kebabFromSnake = utils.kebabFromSnake;

const arg = @import("arg.zig");
const Diag = @import("Diag.zig");

const Error = error{
    AlreadyParsed,
    ExpectValue,
    WrongValueType,
    UnknownArg,
    NamedPositional,
    InvalidArg,
};

pub const AllErrors = std.Io.Writer.Error || Error || ProtoErr;

var prog: []const u8 = "";

fn additionalData(writer: *Writer, field: Type.StructField, comptime padding: usize) !void {
    const pad = " " ** (padding + 4);

    switch (@typeInfo(@field(field.type, "Value"))) {
        .@"enum" => |infos| {
            try writer.print("\n{s}Supported values:\n", .{pad});

            inline for (infos.fields, 0..) |f, i| {
                try writer.print("{s}  {s}{s}", .{
                    pad,
                    f.name,
                    if (i < infos.fields.len - 1) "\n" else "",
                });
            }
        },
        else => {},
    }
}

/// Parsing configuration
pub const Config = struct {
    /// Skips first argument (program name)
    skip_first: bool = true,
};

/// Parses arguments from the iterator. It must declare a function `next` returning either `?[]const u8` or `?[:0]const u8`
pub fn parse(prog_name: []const u8, Args: type, args_iter: anytype, diag: *Diag, config: Config) AllErrors!arg.ParsedArgs(Args) {
    validateIter(args_iter);
    prog = prog_name;
    if (config.skip_first) _ = args_iter.next();

    return parseCmd(Args, args_iter, diag);
}

fn parseCmd(Args: type, args_iter: anytype, diag: *Diag) AllErrors!arg.ParsedArgs(Args) {
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
        arg: while (args_iter.next()) |argument| {
            // constCast allow to modify the text inplace to avoid allocation to convert from kebab-cli-syntax
            // to snake_case structure fields syntaxe
            const arg_parsed = getNameAndValueRanges(@constCast(argument)) catch |err| {
                try diag.print("Invalid argument '{s}'", .{argument});
                return err;
            };
            const name = arg_parsed.name.getText(argument);
            const full_name = arg_parsed.full_name.getText(argument);

            if (!options_started and arg_parsed.is_cmd) {
                inline for (infos.fields) |field| {
                    if (comptime arg.is(field, .cmd)) {
                        if (std.mem.eql(u8, field.name, name)) {
                            @field(res, field.name) = try parseCmd(field.type.Declared, args_iter, diag);
                            break :cmd;
                        }
                    }
                }
            }

            options_started = true;

            inline for (infos.fields) |field| {
                if (matchField(field, arg_parsed.name.getTextEx(argument))) {
                    if (@field(proto.fields, field.name).done) {
                        try diag.print("Already parsed argument '{s}' (or its long/short version)", .{full_name});
                        return error.AlreadyParsed;
                    } else {
                        // Check if it's a positional, can't use them by their name
                        if (field.defaultValue()) |def| if (def.positional) {
                            try diag.print("Can't use '{s}' by it's name as it's a positional argument", .{full_name});
                            return error.NamedPositional;
                        };

                        if (arg_parsed.value) |range| {
                            @field(res, field.name) = argValue(field.type.Value, range.getText(argument)) catch {
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
                            @field(res, field.name) = argValue(@field(field.type, "Value"), argument) catch {
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

fn matchField(field: Type.StructField, arg_name: Span.ToSource) bool {
    return switch (arg_name) {
        .long => |n| std.mem.eql(u8, field.name, n),
        .short => |n| matchFieldShort(field, n),
    };
}

fn matchFieldShort(field: Type.StructField, arg_name: u8) bool {
    if (field.defaultValue()) |def| {
        if (def.short) |short| {
            if (short == arg_name) {
                return true;
            }
        }
    }

    return false;
}

/// Performs some comptime type checking on argument iterator
fn validateIter(iter: anytype) void {
    // It has to be a pointer because we give it to other commands too
    if (@typeInfo(@TypeOf(iter)) != .pointer) @compileError("Iter must be a pointer");

    const T = @TypeOf(iter.*);

    if (!@hasDecl(T, "next")) {
        @compileError("cli_args's type must have a `next` function");
    }
    const ret_type = @typeInfo(@TypeOf(@field(T, "next"))).@"fn".return_type;

    if (ret_type != ?[]const u8 and ret_type != ?[:0]const u8) {
        @compileError("`next` function must return a `[]const u8` or a `[:0]const u8`");
    }
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
    name: Span,
    full_name: Span,
    value: ?Span,
    is_short: bool,
    is_cmd: bool,
};

/// Modifies inplace the text to avoid allocation
fn getNameAndValueRanges(text: []u8) Error!ParsedArgRes {
    const State = enum { start, name, value };

    var dashes: usize = 0;
    var current: usize = 0;
    var name: Span = .{ .end = text.len };
    var value: ?Span = null;

    s: switch (State.start) {
        .start => {
            // If we reached end of argument but still in start, it's an invalid arg
            if (current == text.len) {
                return error.InvalidArg;
            }

            if (text[current] != '-') {
                name.start = current;
                continue :s .name;
            }
            dashes += 1;
            current += 1;
            continue :s .start;
        },
        .name => {
            if (current == text.len) break :s;
            if (text[current] == '-') text[current] = '_';
            if (text[current] == '=') {
                name.end = current;
                current += 1;

                continue :s .value;
            }

            current += 1;
            continue :s .name;
        },
        .value => value = .{ .start = current, .end = text.len },
    }

    return .{
        .name = name,
        .full_name = .{ .end = name.end },
        .value = value,
        .is_short = dashes == 1,
        .is_cmd = text[0] != '-',
    };
}

// ------
//  Help
// ------
pub fn help(Args: type, writer: *Writer) !void {
    const ArgsWithHelp = arg.ArgsWithHelp(Args);

    // 2 for "--" and 2 for indentation
    const max_len = comptime arg.maxLen(ArgsWithHelp) + 4;
    const info = @typeInfo(ArgsWithHelp).@"struct";

    try printUsage(info, writer);
    try printDesc(Args, writer);
    try printCmds(info, writer, max_len);
    try printPositionals(info, writer, max_len);
    try printOptions(info, writer, max_len);
}

pub fn helpToFile(Args: type, file: std.fs.File) !void {
    var buf: [2048]u8 = undefined;
    var writer = file.writer(&buf);
    try help(Args, &writer.interface);
    return writer.interface.flush();
}

fn printUsage(info: Type.Struct, writer: *Writer) !void {
    try writer.writeAll("Usage:\n");
    try writer.print("  {s} [options] [args]\n", .{prog});

    // Check if there is at least one command
    var found = false;
    inline for (info.fields) |field| {
        if (!found and @typeInfo(field.type.Value) == .@"struct") {
            found = true;
            try writer.print("  {s} [commands] [options] [args]\n", .{prog});
        }
    }
    try writer.writeAll("\n");
}

fn printDesc(Args: type, writer: *Writer) !void {
    if (!@hasDecl(Args, "description")) return;

    try writer.writeAll("Description:\n");
    var it = std.mem.splitScalar(u8, Args.description, '\n');

    while (it.next()) |line| {
        try writer.print("  {s}\n", .{line});
    }
    try writer.writeAll("\n");
}

fn printCmds(info: Type.Struct, writer: *Writer, comptime max_len: usize) !void {
    var found = false;

    inline for (info.fields) |field| {
        if (arg.is(field, .cmd)) {
            if (!found) {
                try writer.writeAll("Commands:\n");
            }
            found = true;

            const name = comptime kebabFromSnake(field.name);
            const text = "  " ++ name;

            // Case: cmd: Arg(CmdArgs) = .{}
            if (field.defaultValue()) |def_val| {
                const desc_field = def_val.desc;
                // Case: cmd: Arg(CmdArgs) = .{ .desc = "foo" }
                if (desc_field.len > 0) {
                    try writer.print(
                        "{[text]s:<[width]}  {[description]s}\n",
                        .{ .text = text, .description = def_val.desc, .width = max_len },
                    );
                } else {
                    try writer.print("{s}\n", .{text});
                }
            }
            // Case: cmd: Arg(CmdArgs)
            else {
                try writer.writeAll("  " ++ name ++ "\n");
            }
        }
    }

    if (found) try writer.writeAll("\n");
}

fn printPositionals(info: Type.Struct, writer: *Writer, comptime max_len: usize) !void {
    var found = false;

    inline for (info.fields) |field| {
        comptime var text: []const u8 = "  ";

        // If positional, it is case: arg: Arg(bool) = .{ .positional = true }
        // so always a default value
        if (comptime arg.is(field, .positional)) {
            const def_val = field.defaultValue().?;
            if (!found) {
                try writer.writeAll("Arguments:\n");
            }
            found = true;

            comptime text = text ++ arg.typeStr(field);

            const desc_field = @field(def_val, "desc");
            // Case: arg: Arg(bool) = .{ .desc = "foo" }
            if (desc_field.len > 0) {
                try writer.print(
                    "{[text]s:<[width]}  {[description]s}",
                    .{ .text = text, .description = def_val.desc, .width = max_len },
                );
            } else {
                try writer.print("{s}", .{text});
            }

            try printDefault(field, writer);
            try additionalData(writer, field, max_len);
            try writer.writeAll("\n");
        }
    }

    if (found) try writer.writeAll("\n");
}

fn printOptions(info: Type.Struct, writer: *Writer, comptime max_len: usize) !void {
    try writer.writeAll("Options:\n");

    inline for (info.fields) |field| {
        comptime var text: []const u8 = "  ";

        if (comptime !(arg.is(field, .cmd) or arg.is(field, .positional))) {
            // Case: arg: Arg(bool) = .{}
            if (field.defaultValue()) |def_val| {
                if (def_val.short) |short| {
                    text = text ++ "-" ++ .{short} ++ ", ";
                }

                const type_text = comptime arg.typeStr(field);
                comptime text = text ++ kebabFromSnakeDash(field.name) ++ if (type_text.len > 0) " " ++ type_text else "";

                const desc_field = def_val.desc;
                // Case: arg: Arg(bool) = .{ .desc = "foo" }
                if (desc_field.len > 0) {
                    try writer.print(
                        "{[text]s:<[width]}  {[description]s}",
                        .{ .text = text, .description = def_val.desc, .width = max_len },
                    );
                } else {
                    try writer.print("{s}", .{text});
                }
            }
            // Case: arg: Arg(bool)
            else {
                try writer.writeAll("  " ++ comptime kebabFromSnakeDash(field.name) ++ " " ++ arg.typeStr(field));
            }

            try printDefault(field, writer);
            try additionalData(writer, field, max_len);

            try writer.writeAll("\n");
        }
    }
}

/// Prints argument default value if one
fn printDefault(field: Type.StructField, writer: *Writer) !void {
    if (field.type.default) |default| {
        const Def = @TypeOf(default);
        const info = @typeInfo(Def);

        if (info == .@"enum") {
            try writer.print(" [default: {t}]", .{default});
        } else if (Def == []const u8) {
            try writer.print(" [default: \"{s}\"]", .{default});
        }
        // We don't print [default: false] for bools
        else if (Def != bool) {
            try writer.print(" [default: {any}]", .{default});
        }
    }
}
