# Clarg

Effortless zero allocation cross-plateform command line argument parsing library.
It uses Zig's compile time awesome capabilities to allow the user to only define a structure with the desired arguments.

![CI](https://github.com/martazvch/clarg/actions/workflows/main.yml/badge.svg)

## Installation

Pull the dependency into your Zig project with `zig fetch` command:

```sh
# Replace `<REPLACE ME>` with the version of clarg that you want to use
# See: https://github.com/martazvch/clarg/releases
zig fetch --save https://github.com/martazvch/clarg/archive/refs/tags/<REPLACE ME>.tar.gz
```

Then add the following to your `build.zig` file:

```zig
const clarg = b.dependency("clarg", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("clarg", clarg.module("clarg"));
```

## Features

Clarg support all of the following:

- Argument's default value of type:
    - Int
    - Float
    - String
    - Enums
- Positional arguments
- Required argument
- Sub-commands and nested sub-commands
- Error reporting
- Automatic generation of `help` argument (can be overridden)
- Multiple assignment operators: `=`, `:`, ` ` (use `Config` structure)

## Usage

Full usage example can be found in [the examples folder](examples/).

The following covers most of the features:

```zig
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
    delta: Arg(10.5) = .{ .desc = "delta time between calculations", .short = 'd' },
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
```

If you run `zig build run -- -h` or `zig build run -- --help` you get the following:

```
Usage:
  basic [options] [args]
  basic [commands] [options] [args]

Description:
  Description of the program
  it can be anything

Commands:
  cmd                      operates on input

Arguments:
  <string>
  <string> [default: "/tmp"]

Options:
  --print-ast
  --print-code
  -p, --print-ir           Print IR [required]
  --t0
  --t1 <int>
  --t2 <float>
  --t3 <string>
  --t4 <string>
  --t5 <enum>
                             Supported values:
                               small
                               medium
                               large
  -c, --count <int>        iteration count [default: 5]
  -d, --delta <float>      delta time between calculations [default: 10.5]
  -f, --dir-path <string>  file path [default: "/home"]
  --other-size <enum>      size of binary [default: small]
                             Supported values:
                               small
                               medium
                               large
  -h, --help               Prints this help and exit
```

And if you run `zig build run -- cmd -h` you get:

```
Usage:
  basic [options] [args]

Options:
  -i, --it-count <int>  iteration count [default: 5]
  -o, --op <enum>       operation [default: add]
                          Supported values:
                            add
                            sub
                            mul
                            div
  -h, --help
```

## TODO

- [ ] Implement multiple use of same argument
- [ ] When printing help for a command, the name could indicate command name
- [ ] Verify if multiple args share the same short name
- [ ] Support '--' to start a list of unprocessed arguments passed to the user

