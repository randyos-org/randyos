const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootgfx);

/// Video mode/output protocol found at boot; sizes the framebuffer info
/// handed to the kernel and (via `.output`) gives the base address.
pub const GraphicsInfo = struct {
    output: *uefi.protocol.GraphicsOutput,
    mode_info: *uefi.protocol.GraphicsOutput.Mode.Info,
};

/// Locate graphics output protocol, read current mode. Logs every
/// supported mode too, for debugging.
pub fn locateGraphicsOutput(boot_services: *uefi.tables.BootServices) !GraphicsInfo {
    log.debug("locating graphics output protocol", .{});
    const res = boot_services.locateProtocol(uefi.protocol.GraphicsOutput, null) catch |err| {
        log.err("locating graphics output protocol failed: {s}", .{@errorName(err)});
        return err;
    };
    const graphics_output = res orelse {
        log.err("graphics output protocol not found!", .{});
        return error.NotFound;
    };

    log.debug("querying graphics mode info", .{});
    const mode = graphics_output.mode;
    log.info("current graphics mode = {}", .{mode.mode});

    var i: u32 = 0;
    while (i < mode.max_mode) : (i += 1) {
        const mode_info = graphics_output.queryMode(i) catch |err| {
            log.err("querying graphics mode failed: {s}", .{@errorName(err)});
            return err;
        };

        if (mode.mode == i) {
            log.info("  resolution and pixel format: {}x{} {s}", .{
                mode_info.horizontal_resolution,
                mode_info.vertical_resolution,
                @tagName(mode_info.pixel_format),
            });
        }
    }

    const video_mode_info = graphics_output.queryMode(mode.mode) catch |err| {
        log.err("querying graphics mode failed: {s}", .{@errorName(err)});
        return err;
    };

    return .{ .output = graphics_output, .mode_info = video_mode_info };
}
