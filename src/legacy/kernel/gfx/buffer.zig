//! Off-screen shadow of the framebuffer: one `u32`/pixel, same row-major
//! layout, plain (non-volatile) memory.
//!
//! Framebuffer may be uncacheable, making per-pixel volatile writes slow
//! bus transactions. Draw here instead and bulk-copy the touched span
//! (`Device.presentSpan`) -- fewer, bigger writes, always a win.
//!
//! Owned by `Device` (`back_buffer` field) so all graphics code (boot
//! logo, drawRect/drawBitmap, terminal backends) shares one surface.

const std = @import("std");

const Self = @This();

/// One u32 per pixel. Empty until `init`.
pixels: []u32 = &.{},

pub fn init(self: *Self, allocator: std.mem.Allocator, len: usize) void {
    self.pixels = allocator.alloc(u32, len) catch
        @panic("OOM allocating graphics back buffer");
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
    allocator.free(self.pixels);
    self.pixels = &.{};
}
