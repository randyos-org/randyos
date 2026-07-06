const std = @import("std");
pub const memory = @import("../../memory.zig");

pub const GraphicsDev = @import("../Device.zig");
pub const bmp = @import("../bmp.zig");
pub const transform = @import("../transform.zig");

/// Parse and draw the embedded RandyOS logo, scaled down to fit the current
/// display resolution.
pub fn drawLogo(gd: *GraphicsDev) void {
    const log = std.log.scoped(.kmain_logo);
    const allocator = memory.kernel_page_allocator.allocator;

    const full_size = bmp.parse(allocator, @embedFile("randyos-logo.bmp")) catch |err| {
        log.err("failed to parse embedded logo: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(full_size.pixels);

    const screen_width: usize = gd.pixel_width;
    const screen_height: usize = gd.pixel_height;
    const fit = transform.fitDimensions(full_size.width, full_size.height, screen_width, screen_height);
    const scaled = transform.resize(allocator, full_size, fit.width, fit.height) catch |err| {
        log.err("failed to scale embedded logo: {s}", .{@errorName(err)});
        return;
    };
    defer allocator.free(scaled.pixels);

    const x: u16 = @intCast((screen_width - scaled.width) / 2);
    const y: u16 = @intCast((screen_height - scaled.height) / 2);
    gd.drawBitmap(x, y, scaled);
}
