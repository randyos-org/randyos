//! Advanced Programmable Interrupt Controller
//! 2024 by Samuel Fiedler

const std = @import("std");
const log = std.log.scoped(.arch_lapic);

const registers = @import("registers.zig");
const paging = @import("paging.zig");

/// Global Local APIC Interface
pub var global_apic = APIC{};

/// Local APIC MSR
pub const LapicMSR = packed struct(u64) {
    /// Reserved
    res1: u8 = 0,
    /// BSP Flag
    /// Indicates if the processor is a bootstrap processor.
    bsp: bool,
    /// Reserved
    res2: u2 = 0,
    /// APIC Global Enable Flag
    /// Enables or disables the local APIC
    apic_global_enable: bool,
    /// APIC Base Field
    /// Specifies the base address of the APIC registers. This 24-bit value is extended by 12 bits at the low end to form the 36-bit base address.
    apic_base: u24,
    /// Reserved
    res3: u28 = 0,
};

/// Local APIC Version
pub const LapicVersion = packed struct(u32) {
    /// Version
    version: u8,
    /// Reserved
    res1: u8 = 0,
    /// Max LVT Entry
    max_lvt: u8,
    /// Support for EOI-broadcast suppression
    eoi_broadcast_suppression: bool,
    /// Reserved
    res2: u7 = 0,
};

/// Local APIC
pub const APIC = struct {
    /// Control Base Address
    control_base: usize = 0xfee00000,

    /// Read from the APIC Registers
    pub inline fn read(self: *const APIC, register: Register) u32 {
        const ptr: *align(4) volatile u32 = @ptrFromInt(self.control_base + @intFromEnum(register));
        log.debug("Register {s} has value 0x{x}", .{ @tagName(register), ptr.* });
        return ptr.*;
    }

    /// Write to the APIC Registers
    pub inline fn write(self: *const APIC, register: Register, value: u32) void {
        log.debug("Set register {s} to value 0x{x}", .{ @tagName(register), value });
        const ptr: *align(4) volatile u32 = @ptrFromInt(self.control_base + @intFromEnum(register));
        ptr.* = value;
    }
};

/// Local APIC Registers
pub const Register = enum(usize) {
    /// LAPIC ID Register. In xAPIC mode the 8-bit APIC ID lives in bits
    /// 24-31 of the raw register value; the rest is reserved.
    local_apic_id = 0x20,
    /// LAPIC version Register
    local_apic_version = 0x30,
    /// Task Priority Register
    task_priority = 0x80,
    /// Arbitration Priority Register
    arbitration_priority = 0x90,
    /// Processor Priority Register
    processor_priority = 0xa0,
    /// End Of Interrupt Register
    end_of_interrupt = 0xb0,
    /// Remote Read Register
    remote_read = 0xc0,
    /// Logical Destination Register
    logical_destination = 0xd0,
    /// Destination Format Register
    destination_format = 0xe0,
    /// Spurious Interrupt Vector Register
    spurious_interrupt_vector = 0xf0,
    /// In-Service Register (ISR)
    in_service = 0x100,
    /// Trigger Mode Register (TMR)
    trigger_mode = 0x180,
    /// Interrupt Request Register
    interrupt_request = 0x200,
    /// Error Status Register
    error_status = 0x280,
    /// LVT Corrected Machine Check Interrupt (CMCI) Register
    lvt_corrected_machine_check_interrupt = 0x2f0,
    /// Interrupt Command Register (low)
    interrupt_command_low = 0x300,
    /// Interrupt Command Register (high)
    interrupt_command_high = 0x310,
    /// LVT Timer Register
    lvt_timer = 0x320,
    /// LVT Thermal Sensor Register
    lvt_thermal_sensor = 0x330,
    /// LVT Performance Monitoring Counters Register
    lvt_perf_monitoring_counter = 0x340,
    /// LVT LINT0 Register
    lvt_lint0 = 0x350,
    /// LVT LINT1 Register
    lvt_lint1 = 0x360,
    /// LVT Error Register
    lvt_error = 0x370,
    /// Initial Count Register (for Timer)
    initial_count = 0x380,
    /// Current Count Register (for Timer)
    current_count = 0x390,
    /// Divide Configuration Register (for Timer)
    divide_configuration = 0x3e0,
};

/// IA32 APIC Base MSR address
pub const ia32_apic_base_msr: u16 = 0x1b;

/// Set APIC Base
pub inline fn setMSR(apic: LapicMSR) void {
    const arr: [2]u32 = @bitCast(apic);
    const edx: u32 = arr[1];
    const eax: u32 = arr[0];
    registers.setMSR(ia32_apic_base_msr, .{ .eax = eax, .edx = edx });
}

/// Get APIC Base
pub inline fn getMSR() LapicMSR {
    const value = registers.getMSR(ia32_apic_base_msr);
    return @bitCast((value.eax) | (@as(u64, value.edx) << 32));
}

/// End of Interrupt
pub inline fn eoi() void {
    log.debug("Sending EOI to the Local APIC...", .{});
    global_apic.write(.end_of_interrupt, 0);
    log.debug("Sending EOI to the Local APIC successful!", .{});
}

/// Enable the APIC
/// Assumes that an APIC is available. Only xAPIC (MMIO register access via
/// `control_base`) is supported here -- x2APIC (MSR-based registers) is
/// never enabled, regardless of whether the CPU supports it.
pub fn enable() void {
    var apic_msr: LapicMSR = getMSR();
    apic_msr.apic_global_enable = true;
    setMSR(apic_msr);
    global_apic.control_base = @as(u64, apic_msr.apic_base) << 12;
    log.debug("APIC Base is 0x{x}", .{global_apic.control_base});
    log.debug("Physical from virtual (hex): {?x}", .{paging.physFromVirt(global_apic.control_base)});
}

/// Initialize the APIC
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
