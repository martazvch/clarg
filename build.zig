const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // We will also create a module for our other entry point, 'main.zig'.
    const clarg_mod = b.createModule(.{
        .root_source_file = b.path("src/clarg.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "clarg",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("clarg", clarg_mod);

    b.installArtifact(exe);
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // --------
    // For ZLS
    // --------
    const exe_check = b.addExecutable(.{
        .name = "foo",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
    });
    exe_check.root_module.addImport("clarg", clarg_mod);

    const check = b.step("check", "Check if foo compiles");
    check.dependOn(&exe_check.step);

    // --------
    //  Tests
    // --------
    const exe_unit_tests = b.addTest(.{
        .root_module = clarg_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
