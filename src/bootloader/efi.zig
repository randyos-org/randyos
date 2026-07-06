//! Some additional EFI stuff

const std = @import("std");
const uefi = std.os.uefi;
const log = std.log.scoped(.bootefi);
const pages = @import("common").pages;
const efi_page_shift = pages.page_shift;
const efi_page_mask = pages.page_mask;

/// Convert a memory size to memory pages (4096 bytes each)
pub inline fn efiSizeToPages(value: anytype) @TypeOf(value) {
    const addition: @TypeOf(value) = if (value & efi_page_mask != 0) 1 else 0;
    const ret = (value >> efi_page_shift) + addition;
    return ret;
}
