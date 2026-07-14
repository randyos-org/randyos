const std = @import("std");
const builtin = @import("builtin");
const log = std.log.scoped(.hw);

const common = @import("common");
pub const build_options = common.build_options;

pub const interface = if (build_options.has_acpi)
    @import("acpi/root.zig")
else if (build_options.has_devicetree)
    @import("dtb/root.zig")
else
    struct {};
