const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;
const Alignment = std.mem.Alignment;

const state = @import("state.zig");
const unsupported = @import("__root__.zig").unsupported;

pub fn crashHandler(_: ?*anyopaque) void {
    // Threaded uses this to mark the crashing task canceled so other threads
    // stop cleanly. With one task there is nothing to notify; the panic
    // machinery carries on to print and hang.
}

pub fn async(
    _: ?*anyopaque,
    result: []u8,
    _: Alignment,
    context: []const u8,
    _: Alignment,
    start: *const fn (context: *const anyopaque, result: *anyopaque) void,
) ?*Io.AnyFuture {
    // Run the task eagerly to completion; returning null tells the caller
    // the result is already populated and `await` will be a no-op.
    start(context.ptr, result.ptr);
    return null;
}

pub fn concurrent(
    _: ?*anyopaque,
    _: usize,
    _: Alignment,
    _: []const u8,
    _: Alignment,
    _: *const fn (context: *const anyopaque, result: *anyopaque) void,
) Io.ConcurrentError!*Io.AnyFuture {
    // `concurrent` promises the task runs independently of the caller, which
    // eager execution cannot honor (the caller may block on it in a way that
    // requires true parallelism). Refusing is the documented escape hatch.
    return error.ConcurrencyUnavailable;
}

pub fn await(_: ?*anyopaque, _: *Io.AnyFuture, _: []u8, _: Alignment) void {
    unreachable; // async never returns a non-null future here
}

pub fn cancel(_: ?*anyopaque, _: *Io.AnyFuture, _: []u8, _: Alignment) void {
    unreachable; // async never returns a non-null future here
}

pub fn groupAsync(
    _: ?*anyopaque,
    _: *Io.Group,
    context: []const u8,
    _: Alignment,
    start: *const fn (context: *const anyopaque) void,
) void {
    start(context.ptr);
}

pub fn groupConcurrent(
    _: ?*anyopaque,
    _: *Io.Group,
    _: []const u8,
    _: Alignment,
    _: *const fn (context: *const anyopaque) void,
) Io.ConcurrentError!void {
    return error.ConcurrencyUnavailable;
}

pub fn groupAwait(_: ?*anyopaque, _: *Io.Group, _: *anyopaque) Io.Cancelable!void {
    // Every group task already ran to completion inside groupAsync.
}

pub fn groupCancel(_: ?*anyopaque, _: *Io.Group, _: *anyopaque) void {
    // Nothing in flight to cancel; see groupAwait.
}

/// Per-task state in std's model; there is exactly one task here.
var cancel_protection: Io.CancelProtection = .unblocked;

pub fn swapCancelProtection(_: ?*anyopaque, new: Io.CancelProtection) Io.CancelProtection {
    const prev = cancel_protection;
    cancel_protection = new;
    return prev;
}

pub fn checkCancel(_: ?*anyopaque) Io.Cancelable!void {
    // No other task exists to request cancellation.
}

pub fn recancel(_: ?*anyopaque) void {}

pub fn futexWait(_: ?*anyopaque, _: *const u32, _: u32, _: Io.Timeout) Io.Cancelable!void {
    // Returning immediately is a legal spurious wakeup, and with a single
    // task, actually blocking could only ever deadlock the machine.
}

pub fn futexWaitUncancelable(_: ?*anyopaque, _: *const u32, _: u32) void {
    // Same spurious-wakeup story as futexWait, but this one is used by
    // std.debug to park a panicking task forever in a `while (true)` loop --
    // stall a little so that loop isn't a flat-out busy spin.
    if (state.bootServices()) |bs| bs.stall(1000) catch {};
}

pub fn futexWake(_: ?*anyopaque, _: *const u32, _: u32) void {
    // Nothing can be waiting; see futexWait.
}

pub fn operate(_: ?*anyopaque, _: Io.Operation) Io.Cancelable!Io.Operation.Result {
    unsupported(@src());
}

pub fn batchAwaitAsync(_: ?*anyopaque, _: *Io.Batch) Io.Cancelable!void {
    unsupported(@src());
}

pub fn batchAwaitConcurrent(_: ?*anyopaque, _: *Io.Batch, _: Io.Timeout) Io.Batch.AwaitConcurrentError!void {
    unsupported(@src());
}

pub fn batchCancel(_: ?*anyopaque, _: *Io.Batch) void {
    unsupported(@src());
}
