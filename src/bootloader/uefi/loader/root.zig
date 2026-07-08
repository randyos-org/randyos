//! Module root for the ELF kernel-loading pipeline, split by concern into
//! sibling files (see each one's own doc comment for why it's separate):
//! file_io.zig (generic UEFI file reads), segments.zig (PT_LOAD segments),
//! debug_info.zig (DWARF sections), load_address.zig (placement), and
//! kernel_image.zig (ties them together). Only `loadKernel` is actually
//! used outside this directory, so that's the only re-export.

const std = @import("std");
const log = std.log.scoped(.bootload_root);

const kernel_image = @import("kernel_image.zig");

pub const loadKernel = kernel_image.loadKernel;
