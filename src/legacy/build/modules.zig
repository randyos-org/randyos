//! Build modules shared across every kernel/bootloader target, real and
//! roadmap-stub alike: "common" (code shared between the bootloader and
//! kernel) and "abi" (Linux syscall/ABI-compatibility reference data, kept
//! separate since it's about an *external* contract, not shared code).

const std = @import("std");
const log = std.log.scoped(.build_modules);
const Build = std.Build;
const Target = std.Target;
const Module = Build.Module;
const OptimizeMode = std.builtin.OptimizeMode;
const Options = Build.Step.Options;

const docs_mod = @import("docs.zig");
const Docs = docs_mod.Docs;

/// Real architectures the "abi" module's reference data covers (see
/// src/abi/README.md) -- one doc-only build per entry, since Zig's autodoc
/// can only resolve one branch of a `builtin.cpu.arch`-keyed switch per
/// compilation (`fcntl` in src/abi/fcntl.zig, `mman` in src/abi/mman.zig,
/// `syscall` in src/abi/syscall.zig, and `stat` in src/abi/stat.zig each
/// switch per-field/per-declaration within the file). A single
/// host-targeted doc build would silently only ever document whichever
/// architecture happens to match the machine running `zig build docs` --
/// building one per real arch instead means every architecture's actual
/// (fully resolved) constants show up somewhere, each under its own
/// explicit `abi-<name>` doc page.
const abi_doc_targets = [_]struct { name: []const u8, query: Target.Query }{
    .{ .name = "x86_64", .query = .{ .cpu_arch = .x86_64, .os_tag = .freestanding, .abi = .none } },
    .{ .name = "aarch64", .query = .{ .cpu_arch = .aarch64, .os_tag = .freestanding, .abi = .none } },
    .{ .name = "arm", .query = .{ .cpu_arch = .arm, .os_tag = .freestanding, .abi = .eabi } },
    .{ .name = "ppc", .query = .{ .cpu_arch = .powerpc, .os_tag = .freestanding, .abi = .eabi } },
};

const LoggerScpIgn: type = []const []const u8;

pub fn addCommon(
    b: *Build,
    optimize: OptimizeMode,
    docs: Docs,
    options: *Options,
) *Module {
    const common_mod = b.createModule(.{
        .root_source_file = b.path("src/common/root.zig"),
        // .target = b.resolveTargetQuery(bootloader_query),
        .optimize = optimize,
    });
    common_mod.addOptions("build_options", options);

    // Same "docs-only, host-targeted" trick as `abi` below -- `common_mod`
    // has no fixed target of its own (only ever imported into other
    // target-specific modules), so it needs its own compile object to run
    // `getEmittedDocs()` against.
    const common_docs_mod = b.createModule(.{
        .root_source_file = b.path("src/common/root.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    common_docs_mod.addOptions("build_options", options);
    const common_docs_obj = b.addObject(.{
        .name = "common",
        .root_module = common_docs_mod,
    });
    docs.addModuleDocs(b, common_docs_obj, "common");

    return common_mod;
}

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
        docs.addModuleDocs(b, abi_docs_obj, b.fmt("abi-{s}", .{target.name}));
    }

    return abi_mod;
}

/// The "ghostty-vt" module: VT parsing/terminal state for the fbcon,
/// vendored from a trimmed fork of Ghostty (see src/vendor/ghostty) rather
/// than continuing to hand-roll VT parsing in FBCon. Built without SIMD
/// (`-Dsimd=false`) -- SIMD-accelerated UTF-8 decoding pulls in a vendored
/// C++ simdutf that needs libc, which Zig can't provide for a
/// freestanding/none target; the scalar fallback is pure Zig. Unlike
/// `addCommon`/`addAbi`, this needs a concrete resolved target up front (it
/// isn't target-independent), so it's called from `addKernel` once the
/// kernel's target is resolved, rather than alongside common/abi at the top
/// of `build.zig`.
///
/// Returns `null` on the first `zig build` invocation that hasn't fetched
/// the (local path, so effectively always-available) dependency yet --
/// callers should skip the import in that case, matching `b.lazyDependency`
/// convention.
pub fn addGhosttyVt(
    b: *Build,
    target: Build.ResolvedTarget,
) ?*Module {
    // Always .ReleaseSafe regardless of the kernel's own optimize mode:
    // Ghostty's page/pagelist "slow_runtime_safety" integrity checks
    // (src/vendor/ghostty/src/build_config.zig) are hardcoded on for
    // .Debug builds and allocate via a thread-safe std.heap.DebugAllocator,
    // which pulls in std.Io.Threaded's futex/posix backend -- unimplemented
    // for freestanding. .ReleaseSafe keeps normal safety checks (bounds,
    // overflow, asserts) while skipping that Debug-only slow path.
    const ghostty_dep = b.lazyDependency("ghostty", .{
        .target = target,
        .optimize = .ReleaseSafe,
        .simd = false,
        .embedded = true,
    }) orelse return null;
    return ghostty_dep.module("ghostty-vt");
}
