//! Documentation generation: installing a compile step's emitted docs under
//! `zig-out/docs/<name>/`, plus the shared "docs" step (part of the default
//! `zig build`/`zig build install` step) and `zig build run-docs` for serving
//! the result locally.

const std = @import("std");
const Build = std.Build;
const Step = Build.Step;

/// Install `compile`'s emitted docs under `zig-out/docs/<name>/` and make
/// `target_step` depend on that install.
pub fn addModuleDocsTo(b: *Build, target_step: *Step, compile: *Step.Compile, name: []const u8) void {
    const install = b.addInstallDirectory(.{
        .source_dir = compile.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = b.fmt("docs/{s}", .{name}),
    });
    target_step.dependOn(&install.step);
}

/// Shared handle each `addX` function attaches its own generated docs to,
/// rather than a single function reaching into already-built `*Step.Compile`
/// handles after the fact.
pub const Docs = struct {
    step: *Step,

    /// Install `compile`'s emitted docs under `zig-out/docs/<name>/` and
    /// make the shared "docs" step (part of the default install step) depend
    /// on that install. Only for things that are always expected to build
    /// (common/abi/bootloader/kernel) -- the roadmap arch stubs use
    /// `addModuleDocsTo` directly against their own per-arch step instead,
    /// so a stub that doesn't build yet can't break the default build.
    pub fn addModuleDocs(docs: Docs, b: *Build, compile: *Step.Compile, name: []const u8) void {
        addModuleDocsTo(b, docs.step, compile, name);
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
