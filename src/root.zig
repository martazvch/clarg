const arg = @import("arg.zig");
pub const Arg = arg.Arg;
pub const Diag = @import("Diag.zig");

const utils = @import("utils.zig");
pub const SliceIter = utils.SliceIterator;

const clarg = @import("clarg.zig");
pub const Config = clarg.Config;
pub const parse = clarg.parse;
pub const help = clarg.help;
pub const helpToFile = clarg.helpToFile;

// TODO: check useless use of 'positional', 'required', ... when using a command
// TODO: check if all required arguments have been provided
// TODO: implement required
// TODO: implement multiple use of same arg with different value
// TODO: when printing help for a command, the usage is false because the name of exe is the program name nt the cmd
// TODO: Verify if multiple args share the same short name
