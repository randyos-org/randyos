//! Bootloader entry point dispatcher. `build.zig` points every bootloader
//! target query at this file instead of at a specific implementation
//! directory directly, so adding a new target only means adding a branch
//! here rather than teaching `build.zig` a new root_source_file.
//!
//! Only UEFI is wired up right now (real x86_64 build + aarch64 stub -- see
//! `arch_stubs` in build.zig). `rpi/`, `asahi/`, and `ofw/` are unreached:
//! a bare target triple can't tell a Raspberry Pi 5 apart from an Apple
//! Silicon Mac or a classic PowerPC Mac (all are e.g. plain
//! `aarch64-freestanding-none` or similar), so selecting one of those needs
//! something beyond `builtin.target` -- a build option or a separate target
//! query per board -- that doesn't exist yet.

const std = @import("std");
const log = std.log.scoped(.bootloader);

const builtin = @import("builtin");
const common = @import("common");

const impl = switch (builtin.target.os.tag) {
    .uefi => @import("uefi/main.zig"),
    else => @compileError("no bootloader implementation wired up for this target yet"),
};

// `std.start` looks for `main`/`std_options` by name on the root module --
// re-export them explicitly rather than `usingnamespace` (removed in Zig
// 0.16).
pub const main = impl.main;
pub const std_options = impl.std_options;

// `@import("root")` in src/common/logging.zig resolves to whatever module
// is actually the compilation root -- that's this file now, not
// uefi/main.zig, so the re-export has to live here.
pub const build_options = common.build_options;
