//! ELF kernel-loading pipeline root.

const std = @import("std");
const log = std.log.scoped(.bootload);

const image = @import("image.zig");
const loadaddr = @import("loadaddr.zig");

pub const LoadedKernel = image.LoadedKernel;
pub const loadKernel = image.loadKernel;
pub const KernelLoadPlan = loadaddr.KernelLoadPlan;
pub const moveKernelToDestination = loadaddr.moveKernelToDestination;
