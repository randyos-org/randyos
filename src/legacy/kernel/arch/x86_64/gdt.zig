//! Global Descriptor Table
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_gdt);

const common = @import("common");
const pages = common.pages;

const registers = @import("registers.zig");

extern const __stack_top: u8;
extern const __fault_stack_top: u8;

/// Task State Segment
pub const TSS = extern struct {
    /// Reserved
    _0: u32 align(1) = 0,
    /// RSPs
    rsp: [3]u64 align(1) = @splat(0),
    /// Reserved
    _1: u64 align(1) = 0,
    /// ISTs
    ist: [7]u64 align(1) = @splat(0),
    /// Reserved
    _2: u64 align(1) = 0,
    /// Reserved
    _3: u16 align(1) = 0,
    /// I/O bitmap offset from TSS base. Defaults past TSS end (disables
    /// bitmap) -- ring3 port I/O would #GP.
    io_base: u16 align(1) = @sizeOf(@This()),
};

var global_tss = TSS{};
const ist_vec: u8 = 1;
/// Mask for `ist_vec`: IDT IST field is 3 bits, indexes 1-7 into
/// `TSS.ist` (0 = no stack switch).
const ist_vec_mask: u8 = 0b111;

/// Set an IST slot
pub fn setIST(value: u64) void {
    global_tss.ist[getISTVec() - 1] = value;
}

/// Get IST vector
pub fn getISTVec() u8 {
    return ist_vec & ist_vec_mask;
}

/// GDT entry access byte
pub const Access = packed struct(u8) {
    /// Accessed bit; CPU sets on access unless pre-set
    a: bool = false,
    /// Readable (code) / writable (data) bit
    rw: bool = false,
    /// Direction (data: grow up/down) / conforming (code) bit
    dc: bool = false,
    /// Executable bit: set = code segment
    e: bool = false,
    /// Descriptor type: sys vs code/data
    s: enum(u1) {
        sys = 0,
        data_code = 1,
    } = .sys,
    /// Privilege level: 0 = kernel, 3 = user
    dpl: enum(u2) {
        kernel = 0,
        user = 3,
        _,
    } = .kernel,
    /// Present bit; must be set for a valid segment
    p: bool = false,

    pub const kernel_code = Access{
        .e = true,
        .s = .data_code,
        .p = true,
        .rw = true,
    };
    pub const kernel_data = Access{
        .s = .data_code,
        .p = true,
        .rw = true,
    };
    pub const user_code = Access{
        .e = true,
        .s = .data_code,
        .p = true,
        .rw = true,
        .dpl = .user,
    };
    pub const user_data = Access{
        .s = .data_code,
        .p = true,
        .rw = true,
        .dpl = .user,
    };
};

/// Flags half-byte of a GDT entry
pub const Flags = packed struct(u4) {
    /// Reserved
    res1: u1 = 0,
    /// Long mode flag: set = 64-bit code segment (DB should be clear)
    l: bool = true,
    /// Size flag: 16-bit (clear) vs 32-bit (set) protected mode
    db: bool = false,
    /// Granularity: limit unit is 1B (clear) or 4KB (set)
    g: bool = false,
};

/// GDT entry. Base/limit ignored in 64-bit mode (full linear space either
/// way).
pub const Entry = packed struct(u64) {
    /// Limit low 20 bits; 0xfffff = full 4GB span in 32-bit mode
    limit_low: u16 = 0xffff,
    /// Base low (segment start addr)
    base_low: u24 = 0,
    /// Access bit
    access: Access = .{},
    /// Limit high
    limit_high: u4 = 0xf,
    /// Flags
    flags: Flags = .{},
    /// Base high
    base_high: u8 = 0,

    pub const null_segment: Entry = @bitCast(@as(u64, 0));
    pub const kernel_code = Entry{
        .access = Access.kernel_code,
        .flags = .{
            .g = true,
            .l = true,
        },
    };
    pub const kernel_data = Entry{
        .access = Access.kernel_data,
        .flags = .{
            .g = true,
            .l = true,
        },
    };
    pub const user_code = Entry{
        .access = Access.user_code,
        .flags = .{
            .g = true,
            .l = true,
        },
    };
    pub const user_data = Entry{
        .access = Access.user_data,
        .flags = .{
            .g = true,
            .l = true,
        },
    };
};

/// Access byte of a system entry in the GDT
pub const SystemAccess = packed struct(u8) {
    /// Type of system segment
    type: enum(u4) {
        ldt = 2,
        tss_64bit_available = 9,
        tss_64bit_busy = 11,
    } = .tss_64bit_available,
    /// Descriptor type: sys vs code/data
    s: enum(u1) {
        sys = 0,
        data_code = 1,
    } = .sys,
    /// Privilege level: 0 = kernel, 3 = user
    dpl: enum(u2) {
        kernel = 0,
        user = 3,
        _,
    } = .kernel,
    /// Present bit; must be set for a valid segment
    p: bool = false,

    pub const tss = SystemAccess{
        .type = .tss_64bit_available,
        .p = true,
    };
};

/// System GDT entry
pub const SystemEntry = packed struct(u128) {
    /// Limit low 20 bits; 0xfffff = full 4GB span in 32-bit mode
    limit_low: u16 = 0xffff,
    /// Base low 24 bits, paired w/ base_high for full 64-bit base (system
    /// descriptors are 16B, unlike the 32-bit-only base in `Entry`)
    base_low: u24 = 0,
    /// Access bit
    access: SystemAccess = .{},
    /// Limit high
    limit_high: u4 = 0xf,
    /// Flags
    flags: Flags = .{},
    /// Base high
    base_high: u40 = 0,
    /// Reserved
    res1: u32 = 0,

    /// Low half of entry
    pub fn low(self: SystemEntry) Entry {
        const ptr: *const Entry = @ptrCast(&self);
        return ptr.*;
    }

    /// High half of entry
    pub fn high(self: SystemEntry) Entry {
        const ptr: [*]const Entry = @ptrCast(&self);
        return ptr[1];
    }

    /// TSS entry; fn because tss_addr isn't comptime
    pub fn getTSS() SystemEntry {
        const tss_addr = @intFromPtr(&global_tss);
        return SystemEntry{
            .limit_low = @sizeOf(TSS) - 1,
            .limit_high = 0,
            .base_low = @truncate(tss_addr & 0xffffff),
            .base_high = @truncate(tss_addr >> 24),
            .access = SystemAccess.tss,
            .flags = .{
                .l = false,
                .g = false,
            },
        };
    }
};

/// GDT descriptor
pub const Descriptor = packed struct(u80) {
    /// GDT byte length - 1
    size: u16,
    /// Offset
    offset: u64,
};

/// GDT selectors
pub const Selector = enum(u16) {
    null_segment = 0x00,
    kernel_code = 0x08,
    kernel_data = 0x10,
    user_code = 0x20,
    user_data = 0x28,
    tss = 0x30,
    /// non-exhaustive
    _,
};

/// Entries in `global_gdt`: null, kernel code/data, unused gap selector,
/// user code/data, 2-slot TSS (see `SystemEntry.low`/`.high`)
const gdt_entry_count: usize = 8;

pub var global_gdt: [gdt_entry_count]Entry align(pages.page_size) = undefined;
pub var descriptor: Descriptor = undefined;

/// Init GDT
pub fn init() void {
    log.info("GDT initialization...", .{});
    asm volatile ("cli");
    global_tss.rsp[0] = @intFromPtr(&__stack_top);
    // dedicated fault stack; avoids re-fault on blown stack (see
    // idt.usesTrapStack)
    setIST(@intFromPtr(&__fault_stack_top));
    global_gdt = .{
        Entry.null_segment,
        Entry.kernel_code,
        Entry.kernel_data,

        // gap selector 0x18; unused, Selector skips 0x10 -> 0x20
        Entry.null_segment,

        Entry.user_code,
        Entry.user_data,
        SystemEntry.getTSS().low(),
        SystemEntry.getTSS().high(),
    };
    descriptor = .{
        .size = @sizeOf(Entry) * gdt_entry_count - 1,
        .offset = @intFromPtr(&global_gdt),
    };
    // lgdt
    asm volatile ("lgdt (%[addr])"
        :
        : [addr] "{rax}" (&descriptor),
    );
    // load tss + kernel segments
    asm volatile ("ltr %[val]"
        :
        : [val] "{ax}" (@as(u16, @intFromEnum(Selector.tss))),
    );
    registers.setDataSegments(@intFromEnum(Selector.kernel_data));
    registers.setCS(@intFromEnum(Selector.kernel_code));
    log.info("GDT initialization successful!", .{});
}

test "compile" {
    try std.testing.expect(@sizeOf(TSS) == 104);
}
