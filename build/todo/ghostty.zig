const std = @import("std");
const buildroot = @import("__root__.zig");
const rstdbuild = buildroot.rstd.buildutils;

const Build = rstdbuild.Build;
const RunStep = rstdbuild.RunStep;
const Target = rstdbuild.Target;
const Module = rstdbuild.Module;
const OptimizeMode = rstdbuild.OptimizeMode;
const Options = rstdbuild.Options;
const Docs = rstdbuild.Docs;

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
