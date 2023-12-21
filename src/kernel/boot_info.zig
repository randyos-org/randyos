//! The Kernel Boot Info structures
//! 2023 by Samuel Fiedler

/// Memory Type
pub const MemoryType = enum(u32) {
    ReservedMemoryType,
    LoaderCode,
    LoaderData,
    BootServicesCode,
    BootServicesData,
    RuntimeServicesCode,
    RuntimeServicesData,
    ConventionalMemory,
    UnusableMemory,
    ACPIReclaimMemory,
    ACPIMemoryNVS,
    MemoryMappedIO,
    MemoryMappedIOPortSpace,
    PalCode,
    PersistentMemory,
    MaxMemoryType,
    _,
};

/// Memory Descriptor Attribute
pub const MemoryDescriptorAttribute = packed struct(u64) {
    uc: bool,
    wc: bool,
    wt: bool,
    wb: bool,
    uce: bool,
    _pad1: u7 = 0,
    wp: bool,
    rp: bool,
    xp: bool,
    nv: bool,
    more_reliable: bool,
    ro: bool,
    sp: bool,
    cpu_crypto: bool,
    _pad2: u43 = 0,
    memory_runtime: bool,
};

/// Memory Descriptor
pub const MemoryDescriptor = extern struct {
    type: MemoryType,
    physical_start: u64,
    virtual_start: u64,
    number_of_pages: u64,
    attribute: MemoryDescriptorAttribute,
};

/// Video Mode Info
pub const KernelBootVideoModeInfo = extern struct {
    framebuffer_pointer: *anyopaque,
    horizontal_resolution: u32,
    vertical_resolution: u32,
    pixels_per_scanline: u32,
};

/// Kernel Boot Info
pub const KernelBootInfo = extern struct {
    memory_map: *MemoryDescriptor,
    memory_map_size: usize,
    memory_map_descriptor_size: usize,
    video_mode_info: KernelBootVideoModeInfo,
};
