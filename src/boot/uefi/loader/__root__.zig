//! Module root for the ELF kernel-loading pipeline.

const std = @import("std");
const log = std.log.scoped(.bootload);

const image = @import("image.zig");
const loadaddr = @import("loadaddr.zig");

pub const loadKernel = image.loadKernel;
pub const KernelLoadPlan = loadaddr.KernelLoadPlan;
pub const moveKernelToDestination = loadaddr.moveKernelToDestination;
