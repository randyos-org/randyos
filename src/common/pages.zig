const log = @import("std").log.scoped(.pages);

pub const page_shift: usize = 12;
pub const page_size: usize = 1 << page_shift;
pub const page_mask: usize = page_size - 1;
