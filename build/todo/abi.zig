const std = @import("std");
const buildroot = @import("__root__.zig");
const rstdbuild = buildroot.rstd.build;

const Build = rstdbuild.Build;
const RunStep = rstdbuild.RunStep;
const Target = rstdbuild.Target;
const Module = rstdbuild.Module;
const OptimizeMode = rstdbuild.OptimizeMode;
const Options = rstdbuild.Options;
const Docs = rstdbuild.Docs;

/// The "abi" module: Linux syscall/ABI compatibility reference data (see
/// src/abi/README.md). Kept separate from "common" -- it's reference data
/// about an *external* (Linux's) contract, not code shared between the
/// bootloader and kernel.
pub fn addAbi(
    b: *Build,
    optimize: OptimizeMode,
    docs: Docs,
) *Module {
    const abi_mod = b.createModule(.{
        .root_source_file = b.path("src/abi/root.zig"),
        .optimize = optimize,
    });

    // `abi_mod` above has no fixed target (it's only ever imported into
    // other target-specific modules), so it has nothing of its own to run
    // `getEmittedDocs()` against. Build one docs-only object per real
    // architecture instead of a single host-targeted one -- see
    // `abi_doc_targets`'s doc comment for why.
    for (abi_doc_targets) |target| {
        const abi_docs_mod = b.createModule(.{
            .root_source_file = b.path("src/abi/root.zig"),
            .target = b.resolveTargetQuery(target.query),
            .optimize = optimize,
        });
        const abi_docs_obj = b.addObject(.{
            .name = b.fmt("abi-{s}", .{target.name}),
            .root_module = abi_docs_mod,
        });
        docs.addCompileStepDocs(b, abi_docs_obj, b.fmt("abi-{s}", .{target.name}));
    }

    return abi_mod;
}
