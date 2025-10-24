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

    const example_step = b.step("examples", "Build examples");
    for ([_][]const u8{
        "basic",
    }) |example_name| {
        const example = b.addExecutable(.{
            .name = example_name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{example_name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "clarg", .module = clarg_mod },
                },
            }),
        });
        const install_example = b.addInstallArtifact(example, .{});
        example_step.dependOn(&example.step);
        example_step.dependOn(&install_example.step);
    }

    // --------
    // For ZLS
    // --------
    const exe_check = b.addExecutable(.{
        .name = "foo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic.zig"),
            .target = target,
            .optimize = optimize,
        }),
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
