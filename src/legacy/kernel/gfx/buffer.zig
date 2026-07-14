//! An off-screen shadow of the framebuffer: one `u32` per pixel, same
//! row-major layout (`pixels_per_scanline` x `pixel_height`) as the real
//! framebuffer, but plain (non-`volatile`) memory.
//!
//! This kernel never configures a cache/write-combining attribute, so it may
//! well be mapped uncacheable -- in which case every individual `volatile`
//! pixel write issued directly against it is a full, un-combinable bus
//! transaction. Drawing into this buffer instead and presenting the touched
//! span as one bulk copy (see `Device.presentSpan`) turns thousands of
//! scattered small writes into a handful of large sequential ones, which is a
//! strict improvement regardless of the framebuffer's actual cache attribute
//!
//! Owned by `Device` (see its `back_buffer` field) so every part of the
//! kernel's low-level graphics code shares one buffer: the boot logo, any
//! future direct `drawRect`/`drawBitmap` callers, and terminal backends
//! all draw into and read back from the same surface, rather than each
//! maintaining (and needing to re-synchronize) their own.

const std = @import("std");

const Self = @This();

/// One `u32` per pixel. Empty until `init` runs.
pixels: []u32 = &.{},

pub fn init(self: *Self, allocator: std.mem.Allocator, len: usize) void {
    self.pixels = allocator.alloc(u32, len) catch
        @panic("OOM allocating graphics back buffer");
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.pixels);
    self.pixels = &.{};
}
