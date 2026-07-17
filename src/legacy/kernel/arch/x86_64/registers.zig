//! x86-64 registers
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_registers);

/// CPUID leaf 1 ("Processor Info and Feature Bits"): EAX=this on entry;
/// `CpuFeatures.get` decodes result from ECX/EDX. SDM Vol 2A, 3.3, Table 3-8.
const cpuid_leaf_feature_bits: u32 = 1;

/// CR0: system control flags (SDM Vol 3A, 2.5)
pub const CR0 = packed struct(u64) {
    /// protected mode (set) vs real-address mode (clear)
    pe: bool,
    /// WAIT/FWAIT vs TS flag interaction
    mp: bool,
    /// no x87 FPU present (set) / present (clear); also gates MMX/SSE*
    em: bool,
    /// defers FPU/MMX/SSE context save until next such instruction runs
    ts: bool,
    /// extension type; hardcoded 1 on P6+/Xeon/P4, 387DX support pre-486
    et: bool,
    /// native (set) vs PC-style (clear) x87 error reporting
    ne: bool,
    /// Reserved
    _align1: u10 = 0,
    /// blocks supervisor writes to read-only pages when set
    wp: bool,
    /// Reserved
    _align2: u1 = 0,
    /// automatic alignment checking
    am: bool,
    /// Reserved
    _align3: u10 = 0,
    /// write-through vs write-back cache behavior when CD clear
    nw: bool,
    /// disables internal/external caching when set
    cd: bool,
    /// paging enable
    pg: bool,
    /// Reserved
    _align4: u32 = 0,

    pub fn get() CR0 {
        const value = asm volatile ("mov %cr0, %[ret]"
            : [ret] "={rax}" (-> u64),
        );
        return @bitCast(value);
    }

    pub fn set(cr0: CR0) void {
        const value: u64 = @bitCast(cr0);
        asm volatile ("mov %[val], %cr0"
            :
            : [val] "{rax}" (value),
        );
    }
};

// CR1: reserved

/// CR2: page-fault linear address (SDM Vol 3A, 2.5)
pub const CR2 = packed struct(u64) {
    val: u64,

    pub fn get() CR2 {
        const value = asm volatile ("mov %cr2, %[ret]"
            : [ret] "={rax}" (-> u64),
        );
        return @bitCast(value);
    }

    // setting CR2 isn't a real op
};

/// CR3: base of paging-structure hierarchy + PCD/PWT flags (SDM Vol 3A, 2.5)
pub const CR3 = packed struct(u64) {
    /// Reserved
    _align1: u3 = 0,
    /// write-through for the top-level paging structure
    pwt: bool,
    /// cache-disable for the top-level paging structure
    pcd: bool,
    /// Reserved
    _align2: u7 = 0,
    /// page-directory base
    addr: u52,

    pub fn get() CR3 {
        const value = asm volatile ("mov %cr3, %[ret]"
            : [ret] "={rax}" (-> u64),
        );
        return @bitCast(value);
    }

    pub fn set(cr3: CR3) void {
        const value: u64 = @bitCast(cr3);
        asm volatile ("mov %[val], %cr3"
            :
            : [val] "{rax}" (value),
        );
    }
};

/// CR4: architectural extension enable flags (SDM Vol 3A, 2.5)
pub const CR4 = packed struct(u64) {
    /// virtual-8086 interrupt/exception handling extensions
    vme: bool,
    /// protected-mode virtual interrupt flag (VIF) support
    pvi: bool,
    /// restrict RDTSC to ring 0
    tsd: bool,
    /// DR4/DR5 #UD instead of aliasing (debugging extensions)
    de: bool,
    /// 4MB pages under 32-bit paging
    pse: bool,
    /// >32-bit physical addrs; must be set before IA-32e mode
    pae: bool,
    /// machine-check exception enable
    mce: bool,
    /// global page feature
    pge: bool,
    /// allow RDPMC at any privilege level
    pce: bool,
    /// OS supports FXSAVE/FXRSTOR (and gates SSE*)
    osfxsr: bool,
    /// OS handles unmasked SIMD FP exceptions (#XM)
    osxmmexcpt: bool,
    /// blocks SGDT/SIDT/SLDT/SMSW/STR outside ring 0
    umip: bool,
    /// 5-level paging (57-bit linear addrs) in IA-32e mode
    la57: bool,
    /// VMX operation enable
    vmxe: bool,
    /// SMX operation enable
    smxe: bool,
    /// Reserved
    _align1: u1 = 0,
    /// RDFSBASE/RDGSBASE/WRFSBASE/WRGSBASE enable
    fsgsbase: bool,
    /// process-context identifiers (PCID) enable
    pcide: bool,
    /// XSAVE/XRSTOR + XGETBV/XSETBV (XCR0) enable
    osxsave: bool,
    /// AES Key Locker (LOADIWKEY) enable
    kl: bool,
    /// supervisor-mode execution prevention
    smep: bool,
    /// supervisor-mode access prevention
    smap: bool,
    /// protection keys for user-mode pages (PKRU)
    pke: bool,
    /// control-flow enforcement technology
    cet: bool,
    /// protection keys for supervisor-mode pages (IA32_PKRS)
    pks: bool,
    /// user interrupts enable
    uintr: bool,
    /// Reserved
    _align2: u38 = 0,

    pub fn get() CR4 {
        const value = asm volatile ("mov %cr4, %[ret]"
            : [ret] "={rax}" (-> u64),
        );
        return @bitCast(value);
    }

    pub fn set(cr4: CR4) void {
        const value: u64 = @bitCast(cr4);
        asm volatile ("mov %[val], %cr4"
            :
            : [val] "{rax}" (value),
        );
    }
};

/// CR8: Task Priority Register access (SDM Vol 3A, 2.5)
pub const CR8 = packed struct(u64) {
    /// blocks interrupts at/below this priority; 0 = all enabled, 15 = all disabled
    tpl: u4,
    /// Reserved
    _align1: u60 = 0,

    pub fn get() CR8 {
        const value = asm volatile ("mov %cr8, %[ret]"
            : [ret] "={rax}" (-> u64),
        );
        return @bitCast(value);
    }

    pub fn set(cr8: CR8) void {
        const value: u64 = @bitCast(cr8);
        asm volatile ("mov %[val], %cr8"
            :
            : [val] "{rax}" (value),
        );
    }
};

/// CPUID(EAX=01h) feature bits (SDM Vol 2A, 3.3, Table 3-10/3-11)
pub const CpuFeatures = packed struct(u64) {
    // ECX

    sse3: bool,
    pclmulqdq: bool,
    /// 64-bit DS area layout
    dtes64: bool,
    monitor: bool,
    /// CPL-qualified debug store
    ds_cpl: bool,
    vmx: bool,
    /// safer mode extensions
    smx: bool,
    /// enhanced SpeedStep
    eist: bool,
    /// thermal monitor 2
    tm2: bool,
    ssse3: bool,
    /// L1 context ID (adaptive/shared mode)
    cnxt_id: bool,
    /// IA32_DEBUG_INTERFACE MSR (silicon debug)
    sdbg: bool,
    /// FMA using YMM state
    fma: bool,
    cmpxchg16b: bool,
    /// can change IA32_MISC_ENABLE[32]
    xtpr_update_control: bool,
    /// IA32_PERF_CAPABILITIES MSR
    pdcm: bool,
    /// Reserved
    _align1: u1 = 0,
    /// process-context identifiers
    pcid: bool,
    /// prefetch from MMIO device
    dca: bool,
    sse4_1: bool,
    sse4_2: bool,
    x2apic: bool,
    movbe: bool,
    popcnt: bool,
    /// one-shot LAPIC timer via TSC deadline
    tsc_deadline: bool,
    aesni: bool,
    /// XSAVE/XRSTOR + XSETBV/XGETBV, XCR0
    xsave: bool,
    /// OS set CR4.OSXSAVE
    osxsave: bool,
    avx: bool,
    /// 16-bit float conversion instr
    f16c: bool,
    rdrand: bool,
    /// Always 0
    not_used: u1 = 0,

    // EDX

    /// x87 FPU on-chip
    fpu: bool,
    /// virtual-8086 mode enhancements
    vme: bool,
    /// I/O breakpoints (DR4/DR5 trapping)
    de: bool,
    /// 4MB pages (32-bit paging)
    pse: bool,
    /// RDTSC supported
    tsc: bool,
    /// RDMSR/WRMSR supported
    msr: bool,
    /// >32-bit phys addrs
    pae: bool,
    /// machine-check exception (#18)
    mce: bool,
    /// CMPXCHG8B
    cx8: bool,
    /// on-chip APIC (MMIO FFFE0000-FFFE0FFF)
    apic: bool,
    /// Reserved
    _align2: u1 = 0,
    /// SYSENTER/SYSEXIT
    sep: bool,
    /// memory type range registers
    mtrr: bool,
    /// global bit in paging entries
    pge: bool,
    /// machine check architecture
    mca: bool,
    /// CMOV (and FCOMI/FCMOV if FPU present)
    cmov: bool,
    /// page attribute table
    pat: bool,
    /// 36-bit 4MB pages
    pse_36: bool,
    /// 96-bit processor serial number
    psn: bool,
    clfsh: bool,
    /// Reserved
    _align3: u1 = 0,
    /// debug store to memory buffer
    ds: bool,
    /// thermal monitor + software clock control
    acpi: bool,
    mmx: bool,
    fxsr: bool,
    sse: bool,
    sse2: bool,
    /// self snoop (conflicting memory types)
    ss: bool,
    /// CPUID.1.EBX[23:16] APIC ID field valid
    htt: bool,
    /// thermal monitor (TCC)
    tm: bool,
    /// Reserved
    _align4: u1 = 0,
    /// pending break enable (FERR#/PBE# in stop-clock state)
    pbe: bool,

    pub fn get() CpuFeatures {
        return asm volatile ("cpuid; shlq $32, %rdx; or %rdx, %rcx"
            : [ret] "={rcx}" (-> CpuFeatures),
            : [param] "{eax}" (cpuid_leaf_feature_bits),
            : .{
              .rcx = true,
              .rdx = true,
            });
    }
};

pub inline fn getRSP() usize {
    return asm volatile ("mov %rsp, %[ret]"
        : [ret] "={rax}" (-> usize),
    );
}

pub inline fn getIP() usize {
    return asm volatile ("lea (%rip), %[ret]"
        : [ret] "={rax}" (-> usize),
    );
}

/// Jump to `ip` on new stack `sp`, passing `param` as first arg (via rdi,
/// SysV callconv) -- e.g. handoff to a freshly built stack frame
pub inline fn jumpIP(ip: usize, sp: usize, param: anytype) noreturn {
    asm volatile ("push %[ip]; ret"
        :
        : [ip] "{rax}" (ip),
          [sp] "{rsp}" (sp - 8),
          [bp] "{rbp}" (sp - 8),
          [param] "{rdi}" (param),
    );

    while (true) {}
}

pub inline fn setCS(value: u16) void {
    // CS can't be loaded via MOV; load then switch via far return
    _ = asm volatile (
        \\push %[val]
        \\lea setCSOut(%rip), %[tmp]
        \\push %[tmp]
        \\lretq
        \\setCSOut:
        : [tmp] "={rax}" (-> usize),
        : [val] "{rcx}" (@as(u64, value)),
        : .{ .memory = true });
}

/// Set DS, ES, FS, GS, SS
pub inline fn setDataSegments(value: u16) void {
    asm volatile (
        \\movw %[val], %ds
        \\movw %[val], %es
        \\movw %[val], %fs
        \\movw %[val], %gs
        \\movw %[val], %ss
        :
        : [val] "{rax}" (value),
    );
}

pub const MSR = packed struct(u64) {
    eax: u32,
    edx: u32,
};

pub inline fn setMSR(register: u32, value: MSR) void {
    asm volatile ("wrmsr"
        :
        : [low] "{eax}" (value.eax),
          [high] "{edx}" (value.edx),
          [reg] "{ecx}" (register),
    );
}

// TODO: add register enum for MSR

pub inline fn getMSR(register: u32) MSR {
    var eax: u32 = 0;
    var edx: u32 = 0;
    asm volatile ("rdmsr"
        : [low] "={eax}" (eax),
          [high] "={edx}" (edx),
        : [reg] "{ecx}" (register),
    );
    return .{
        .eax = eax,
        .edx = edx,
    };
}

pub const RFLAGS = packed struct(u64) {
    cf: bool,
    /// Reserved
    _align1: u1 = 1,
    pf: bool,
    /// Reserved
    _align2: u1 = 0,
    af: bool,
    /// Reserved
    _align3: u1 = 0,
    zf: bool,
    sf: bool,
    /// trap flag (single-step)
    tf: bool,
    /// interrupt enable
    @"if": bool,
    df: bool,
    of: bool,
    iopl: u2,
    /// nested task
    nt: bool,
    /// Reserved
    _align4: u1 = 0,
    /// resume flag
    rf: bool,
    /// virtual-8086 mode
    vm: bool,
    /// alignment check / access control
    ac: bool,
    /// virtual interrupt flag
    vif: bool,
    /// virtual interrupt pending
    vip: bool,
    /// ID flag
    id: bool,
    /// Reserved
    _align5: u42,
};

pub inline fn getRFLAGS() RFLAGS {
    return asm volatile (
        \\pushfq
        \\pop %[ret]
        : [ret] "={rax}" (-> RFLAGS),
    );
}

pub inline fn setRFLAGS(rflags: RFLAGS) void {
    asm volatile (
        \\push %[val]
        \\popfq
        :
        : [val] "{rax}" (rflags),
    );
}

pub inline fn invlpg(entry: usize) void {
    asm volatile ("invlpg (%[entry])"
        :
        : [entry] "{rax}" (entry),
    );
}

// TODO: maybe move this into another namespace?
pub inline fn halt() void {
    asm volatile ("hlt");
}
