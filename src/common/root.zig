//! Module root for the "common" package shared by both the bootloader and
//! kernel targets (see build.zig) -- just re-exports; add new shared modules
//! here rather than importing them by relative path from elsewhere.

pub const build_options = @import("build_options");
pub const boot_info = @import("boot_info.zig");
pub const pages = @import("pages.zig");
pub const logging = @import("logging.zig");
pub const Terminal = @import("Terminal.zig");
pub const ansi = @import("ansi.zig");
