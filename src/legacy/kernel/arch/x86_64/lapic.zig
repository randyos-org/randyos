//! Local APIC
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_lapic);

const common = @import("common");
const pages = common.pages;
const registers = @import("registers.zig");
const paging = @import("paging.zig");

pub var global_apic = APIC{};

pub const LapicMSR = packed struct(u64) {
    /// Reserved
    res1: u8 = 0,
    /// set if this is the bootstrap processor
    bsp: bool,
    /// Reserved
    res2: u2 = 0,
    /// enables/disables the local APIC
    apic_global_enable: bool,
    /// APIC MMIO base; 24 bits, extended by 12 low bits to a 36-bit addr
    apic_base: u24,
    /// Reserved
    res3: u28 = 0,
};

pub const LapicVersion = packed struct(u32) {
    version: u8,
    /// Reserved
    res1: u8 = 0,
    max_lvt: u8,
    eoi_broadcast_suppression: bool,
    /// Reserved
    res2: u7 = 0,
};

pub const APIC = struct {
    /// standard xAPIC MMIO base every x86_64 system resets to; `enable()`
    /// overwrites with `getMSR().apic_base` in case firmware relocated it
    control_base: usize = 0xfee00000,

    pub inline fn read(self: *const APIC, register: Register) u32 {
        const ptr: *align(4) volatile u32 = @ptrFromInt(self.control_base + @intFromEnum(register));
        log.debug("Register {s} has value 0x{x}", .{ @tagName(register), ptr.* });
        return ptr.*;
    }

    pub inline fn write(self: *const APIC, register: Register, value: u32) void {
        log.debug("Set register {s} to value 0x{x}", .{ @tagName(register), value });
        const ptr: *align(4) volatile u32 = @ptrFromInt(self.control_base + @intFromEnum(register));
        ptr.* = value;
    }
};

/// Local APIC registers
pub const Register = enum(usize) {
    /// xAPIC mode: 8-bit APIC ID in bits 24-31, rest reserved
    local_apic_id = 0x20,
    local_apic_version = 0x30,
    task_priority = 0x80,
    arbitration_priority = 0x90,
    processor_priority = 0xa0,
    end_of_interrupt = 0xb0,
    remote_read = 0xc0,
    logical_destination = 0xd0,
    destination_format = 0xe0,
    spurious_interrupt_vector = 0xf0,
    in_service = 0x100,
    trigger_mode = 0x180,
    interrupt_request = 0x200,
    error_status = 0x280,
    lvt_corrected_machine_check_interrupt = 0x2f0,
    interrupt_command_low = 0x300,
    interrupt_command_high = 0x310,
    lvt_timer = 0x320,
    lvt_thermal_sensor = 0x330,
    lvt_perf_monitoring_counter = 0x340,
    lvt_lint0 = 0x350,
    lvt_lint1 = 0x360,
    lvt_error = 0x370,
    initial_count = 0x380,
    current_count = 0x390,
    divide_configuration = 0x3e0,
};

pub const ia32_apic_base_msr: u16 = 0x1b;

pub inline fn setMSR(apic: LapicMSR) void {
    const arr: [2]u32 = @bitCast(apic);
    const edx: u32 = arr[1];
    const eax: u32 = arr[0];
    registers.setMSR(ia32_apic_base_msr, .{ .eax = eax, .edx = edx });
}

pub inline fn getMSR() LapicMSR {
    const value = registers.getMSR(ia32_apic_base_msr);
    return @bitCast((value.eax) | (@as(u64, value.edx) << 32));
}

pub inline fn eoi() void {
    log.debug("Sending EOI to the Local APIC...", .{});
    global_apic.write(.end_of_interrupt, 0);
    log.debug("Sending EOI to the Local APIC successful!", .{});
}

/// Assumes an APIC is available. Only xAPIC (MMIO via `control_base`) is
/// supported -- x2APIC is never enabled even if the CPU supports it.
pub fn enable() void {
    var apic_msr: LapicMSR = getMSR();
    apic_msr.apic_global_enable = true;
    setMSR(apic_msr);
    global_apic.control_base = @as(u64, apic_msr.apic_base) << pages.page_shift;
    log.debug("APIC Base is 0x{x}", .{global_apic.control_base});
    log.debug("Physical from virtual (hex): {?x}", .{paging.kernelAddressSpace().physFromVirt(global_apic.control_base)});
}

pub fn init() void {
    log.info("APIC initialization... ", .{});
    const cpuid_out = registers.CpuFeatures.get();
    if (cpuid_out.apic) {
        log.debug("CPU has builtin APIC", .{});
        enable();
        log.debug("Local APIC Version: {}", .{@as(LapicVersion, @bitCast(global_apic.read(.local_apic_version)))});
    } else {
        log.warn("CPU has no APIC, skipping the programmable interrupt controller", .{});
    }
    log.info("APIC initialization successful! ", .{});
}
