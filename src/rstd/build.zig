const std = @import("std");
pub const Build = std.Build;
pub const Step = Build.Step;
pub const BuildDir = Step.WriteFile;
pub const InstallDir = Step.InstallDir;
pub const OptimizeMode = std.builtin.OptimizeMode;
pub const TargetQuery = std.Target.Query;
pub const RunStep = Step.Run;
pub const CompileStep = Step.Compile;
pub const Module = Build.Module;
pub const BuildOptions = Step.Options;
pub const ResolvedTarget = Build.ResolvedTarget;

pub fn getOptimize(b: *Build) OptimizeMode {
    return b.standardOptimizeOption(.{});
}

pub fn addBuildDir(b: *Build) *BuildDir {
    return b.addWriteFiles();
}

/// Install `compile`'s emitted docs under `zig-out/docs/<name>/` and make
/// `target_step` depend on that install.
pub fn addCompileStepDocsToStep(b: *Build, target_step: *Step, compile: *CompileStep, name: []const u8) void {
    const install = b.addInstallDirectory(.{
        .source_dir = compile.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = b.fmt("docs/{s}", .{name}),
    });
    target_step.dependOn(&install.step);
}

/// Common docs build step handler struct
pub const Docs = struct {
    step: *Step,

    /// Install `compile`'s emitted docs under `zig-out/docs/<name>/` and
    /// make the shared "docs" step (part of the default install step) depend
    /// on that install. Only for things that are always expected to build.
    /// Docs for other architectures should call `addCompileStepDocsToStep`
    /// directly against their own per-arch step instead so a stub that doesn't
    /// build yet or can't cross-compile can't break the current build.
    pub fn addCompileStepDocs(docs: Docs, b: *Build, compile: *CompileStep, name: []const u8) void {
        addCompileStepDocsToStep(b, docs.step, compile, name);
    }
};

pub fn addDocs(b: *Build) Docs {
    const docs_step = b.step("docs", "Generate and install API documentation");
    // Also run as part of the default `zig build`/`zig build install`, not
    // just when `zig build docs` is requested explicitly.
    b.getInstallStep().dependOn(docs_step);

    const docs_port = b.option(u16, "docs-port", "Port for `zig build run-docs` to serve documentation on") orelse 3000;
    const run_docs_step = b.step("run-docs", "Serve the generated documentation locally");
    const server_cmd = b.addSystemCommand(&.{
        "python", "-m", "http.server", b.fmt("{d}", .{docs_port}), "-b", "127.0.0.1", "-d", "zig-out/docs/",
    });
    server_cmd.step.dependOn(docs_step);
    run_docs_step.dependOn(&server_cmd.step);

    return .{ .step = docs_step };
}

pub fn addBuildOptionsModule(b: *Build) *BuildOptions {
    return b.addOptions();
}

pub fn addBuildOptsModToModule(build_options: *BuildOptions, module: *Module) void {
    module.addOptions("build_options", build_options);
}
