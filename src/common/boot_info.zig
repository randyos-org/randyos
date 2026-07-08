const std = @import("std");
const log = std.log.scoped(.common_boot_info);

const acpi = @import("acpi.zig");
const dtb = @import("dtb.zig");

/// Firmware-neutral classification of a physical memory region, as reported
/// by whatever firmware/bootloader actually handed the kernel its boot
/// info -- the kernel only ever sees this shape, never a raw
/// firmware-native memory map format.
pub const MemoryRegionKind = enum {
    usable,
    reserved,
    acpi_reclaimable,
    acpi_nvs,
    bootloader_reclaimable,
    kernel_and_modules,
    mmio,
    bad,
};

/// A single physical memory region, in firmware-neutral form.
pub const MemoryRegion = struct {
    phys_start: u64,
    page_count: u64,
    kind: MemoryRegionKind,
};

/// Framebuffer pixel channel order, in firmware-neutral form.
pub const FramebufferPixelFormat = enum {
    /// Red, Green, Blue, Reserved
    rgb,
    /// Blue, Green, Red, Reserved
    bgr,
};

/// How this platform describes its hardware (interrupt controllers, memory
/// layout details beyond the bare `memory_map`, etc.) -- payloads are
/// opaque pointers to whatever firmware-native structure applies, so this
/// stays a pure marker + handoff, with zero firmware-specific types leaking
/// into `common`. `null` on `KernelBootInfo` means no hardware description
/// is available at all (shouldn't happen for any real, working target
/// today, but a bootloader is free to report it if it genuinely can't find
/// one). The consuming side (`src/kernel/hw/acpi/root.zig` for `.acpi`
/// today; a future `.devicetree` consumer once a devicetree-based
/// bootloader exists) lives entirely in the kernel, dispatched by
/// arch-specific code (e.g. `src/kernel/arch/x86_64/platform.zig`) rather
/// than the shared `kmain` body -- see `src/common/acpi.zig` for the
/// `.acpi` payload type.
pub const HardwareDescription = union(enum) {
    acpi: acpi.AcpiHardwareDescription,
    /// Unused until a devicetree-based bootloader (`rpi`/`ofw`/`asahi`)
    /// actually exists -- the variant exists now so that day doesn't
    /// require touching this type. See `src/common/dtb.zig`.
    devicetree: dtb.Dtb,
};

/// A firmware runtime environment's own native handle, opaque at this
/// layer on purpose: `common` (shared by every bootloader and the kernel)
/// must never import a firmware-specific module like `std.os.uefi` just to
/// give this field a type. `null` on `KernelBootInfo` means no ongoing
/// firmware runtime is available (the common case -- BIOS, a bare
/// devicetree/U-Boot board with no EFI compatibility layer, etc.).
///
/// Deliberately *not* a set of kernel-callable function pointers: the
/// prior design (a bootloader-authored trampoline, or a wrapped capability
/// struct) was rejected in favor of handing the raw native pointer through
/// unmodified and letting a dedicated, dynamically-loaded firmware driver
/// (see `src/drivers/uefi/root.zig`) interpret it -- that driver only gets
/// linked in on builds/platforms that actually want the (rare, low-
/// priority) extra capabilities a firmware runtime offers beyond what
/// `HardwareDescription` and direct hardware access already cover (see the
/// reset/shutdown discussion: ACPI's FADT reset register, PSCI, and
/// straight hardware pokes cover the common cases without any firmware
/// runtime at all). No driver-loading mechanism exists yet -- this field
/// and `src/drivers/uefi/root.zig` are stubs, wired up for real once a
/// kernel driver-loading capability exists.
pub const FirmwareRuntimeData = union(enum) {
    uefi: *anyopaque,
};

/// Video Mode Info
pub const KernelBootVideoModeInfo = struct {
    framebuffer_pointer: [*]volatile u32,
    framebuffer_size: usize,
    horizontal_resolution: u32,
    vertical_resolution: u32,
    pixels_per_scanline: u32,
    pixel_format: FramebufferPixelFormat,
};

/// Kernel Boot Info
pub const KernelBootInfo = struct {
    memory_map: []const MemoryRegion,
    video_mode_info: KernelBootVideoModeInfo,
    hardware_description: ?HardwareDescription,
    /// See `FirmwareRuntimeData` -- `null` unless a firmware runtime
    /// environment (e.g. UEFI) is actually present.
    fw_runtime_ptr: ?FirmwareRuntimeData,
    kernel_phys_start: usize,
    kernel_phys_end: usize,
    kernel_virt_start: usize,
    kernel_virt_end: usize,
    dwarf_info: *?std.debug.Dwarf,
    /// Unix epoch seconds at boot, as reported by firmware. `null` if the
    /// bootloader couldn't determine a wall-clock time.
    boot_wall_clock_unix_seconds: ?i64,
};
