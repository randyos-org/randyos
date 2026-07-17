const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootwdog);

/// Disable the watchdog timer. Boot Services kills the running image
/// after 5 min by default; jumping into the kernel doesn't stop it from
/// *thinking* the bootloader is still running, so it'd fire under the
/// kernel later otherwise.
pub fn disableWatchdogTimer(boot_services: *uefi.tables.BootServices) !void {
    // zero timeout disables watchdog entirely; code only matters when re-arming
    const watchdog_disabled_timeout_seconds: usize = 0;
    const watchdog_code: u64 = 0;
    log.debug("disabling watchdog timer", .{});
    boot_services.setWatchdogTimer(watchdog_disabled_timeout_seconds, watchdog_code, null) catch |err| {
        log.err("disabling watchdog timer failed: {s}", .{@errorName(err)});
        return err;
    };
    log.debug("watchdog timer disabled", .{});
}
