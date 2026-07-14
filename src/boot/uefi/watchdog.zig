const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootwdog);

/// Disable the watchdog timer. Boot Services normally kill the running
/// image after 5 minutes by default; since jumping into the kernel doesn't
/// stop boot services from *thinking* the bootloader image is still
/// running, the watchdog would otherwise fire under the kernel later.
pub fn disableWatchdogTimer(boot_services: *uefi.tables.BootServices) !void {
    // A zero timeout (in seconds) disables the watchdog entirely; the
    // watchdog code is only meaningful when re-arming it, so it's left 0.
    const watchdog_disabled_timeout_seconds: usize = 0;
    const watchdog_code: u64 = 0;
    log.debug("disabling watchdog timer", .{});
    boot_services.setWatchdogTimer(watchdog_disabled_timeout_seconds, watchdog_code, null) catch |err| {
        log.err("disabling watchdog timer failed: {s}", .{@errorName(err)});
        return err;
    };
    log.debug("watchdog timer disabled", .{});
}
