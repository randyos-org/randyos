const std = @import("std");

const rstd = @import("rstd");
const rio = rstd.io;

pub const loader = @import("loader/__root__.zig");
pub const memory = @import("memory.zig");
pub const logging = @import("logging.zig");
pub const graphics = @import("graphics.zig");
pub const bootinfomod = @import("bootinfo.zig");
pub const watchdog = @import("watchdog.zig");

pub const zigcfg = @import("zigcfg.zig");
pub const main = @import("__main__.zig").main;

/// SBAT metadata (https://github.com/rhboot/shim/blob/main/SBAT.md); shim
/// refuses images without it. Raising randyos' generation (second field)
/// lets a future SbatLevel revoke older builds.
export const sbat linksection(".sbat") = ( //
    "sbat,1,SBAT Version,sbat,1,https://github.com/rhboot/shim/blob/main/SBAT.md\n" ++ //
        "randyos,1,RandyOS,randyos," ++ @import("boot_options").version ++ ",https://codeberg.org/randyos/randyos\n" //
).*;
