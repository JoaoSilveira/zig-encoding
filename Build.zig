const Builder = @import("std").build.Builder;
// source encoding https://encoding.spec.whatwg.org

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const lib = b.addStaticLibrary("encoding", "src/main.zig");
    lib.setBuildMode(mode);
    lib.install();

    var main_tests = b.addTest("src/main.zig");
    main_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&main_tests.step);

    const executable = b.addExecutable("main", "src/main.zig");
    executable.setBuildMode(mode);
    executable.setOutputDir("bin");
    executable.install();

    const exe = executable.run();
    exe.step.dependOn(&executable.step);

    const run = b.step("run", "Run the main file");
    run.dependOn(&exe.step);
}
