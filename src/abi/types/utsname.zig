//! Linux `struct new_utsname`, returned by the `uname` syscall.
//!
//! Sourced from the Linux kernel source tree (`include/uapi/linux/utsname.h`),
//! torvalds/linux @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2), by fetching
//! that file directly and mechanically extracting the struct layout -- not
//! transcribed by hand. Re-derive from that same file if this ever looks
//! stale; do not hand-edit fields here.
//!
//! This layout is fully uniform across every architecture -- there is no
//! per-arch override of `struct new_utsname` in this header or elsewhere at
//! this commit. Each field is `char[__NEW_UTS_LEN + 1]` where
//! `__NEW_UTS_LEN` is 64, i.e. `char[65]`.
//!
//! Fields are `[65]u8` rather than `[65:0]u8`: a Zig sentinel-terminated
//! array type `[N:s]T` reserves `N + 1` elements of storage (the sentinel is
//! an extra byte beyond the N given), which would make each field 66 bytes
//! wide and break the `extern struct`'s byte-for-byte match with the C
//! layout. `[65]u8` is the fixed 65-byte C array this struct actually has;
//! callers still get a NUL-terminated C string within those 65 bytes, they
//! just don't get compile-time sentinel enforcement on the type itself.
//!
//! Not wired to any dispatcher -- this is a layout reference only.

const std = @import("std");
const log = std.log.scoped(.abi_types_utsname);

pub const NewUtsname = extern struct {
    /// Operating system name (e.g. "Linux").
    sysname: [65]u8,
    /// Network hostname of this machine.
    nodename: [65]u8,
    /// OS release, e.g. the kernel version string.
    release: [65]u8,
    /// OS version string, typically build date/info.
    version: [65]u8,
    /// Hardware architecture identifier (e.g. "x86_64").
    machine: [65]u8,
    /// NIS/YP domain name.
    domainname: [65]u8,
};
