//! Bootloader entry point dispatcher.

const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.bootloader);

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
