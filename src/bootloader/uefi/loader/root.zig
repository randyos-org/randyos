//! Module root for the ELF kernel-loading pipeline.
//!
//! Only `loadKernel` is actually used outside this directory,
//! so that's the only re-export.

const std = @import("std");
const log = std.log.scoped(.bootload_root);

const kernel_image = @import("kernel_image.zig");

pub const loadKernel = kernel_image.loadKernel;
