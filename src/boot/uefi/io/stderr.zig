const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;

const uefi_io = @import("__root__.zig").uefi_io;
const state = @import("state.zig");

/// Transcribe bytes to UCS-2 and write them to the UEFI console, expanding
/// "\n" to "\r\n" (Simple Text Output moves down a row on LF but does not
/// return the column). Assumes ASCII: each byte becomes one UTF-16 code unit
/// with no UTF-8 decoding, so multi-byte UTF-8 sequences come out wrong.
fn putsConsole(bytes: []const u8) void {
    const out = state.con_out orelse return;
    // Batched so each outputString call carries a chunk, not one call per
    // character: outputString is a firmware call and can be visibly slow.
    var buf: [64:0]u16 = undefined;
    var len: usize = 0;
    for (bytes) |byte| {
        if (len + 2 > buf.len) {
            buf[len] = 0;
            _ = out.outputString(buf[0..len :0]) catch false;
            len = 0;
        }
        if (byte == '\n') {
            buf[len] = '\r';
            len += 1;
        }
        buf[len] = byte;
        len += 1;
    }
    if (len > 0) {
        buf[len] = 0;
        _ = out.outputString(buf[0..len :0]) catch false;
    }
}

/// `LockedStderr.file_writer` must point at an `Io.File.Writer`, but nothing
/// in the stderr path ever touches its `file` handle: all writes go through
/// `interface`, whose vtable is ours. So the `File` here is a dummy (UEFI's
/// `File.Handle` is `void` anyway) and `stderrDrain` is what actually runs.
var stderr_writer: Io.File.Writer = .{
    .io = uefi_io,
    .file = .{ .handle = {}, .flags = .{ .nonblocking = false } },
    .mode = .streaming_simple,
    .interface = .{
        .vtable = &stderr_writer_vtable,
        .buffer = &.{},
    },
};

const stderr_writer_vtable: Io.Writer.VTable = .{
    .drain = stderrDrain,
};

fn stderrDrain(w: *Io.Writer, data: []const []const u8, splat: usize) Io.Writer.Error!usize {
    const buffered = w.buffered();
    putsConsole(buffered);
    var n: usize = buffered.len;
    if (data.len != 0) {
        for (data[0 .. data.len - 1]) |chunk| {
            putsConsole(chunk);
            n += chunk.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| putsConsole(last);
        n += last.len * splat;
    }
    return w.consume(n);
}

/// Recursion depth rather than a mutex: there's a single thread, but the
/// lock is documented as recursive so the panic handler can re-enter it
/// while a log line holds it.
var stderr_lock_count: u32 = 0;

pub fn lockStderr(_: ?*anyopaque, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!Io.LockedStderr {
    stderr_lock_count += 1;
    return .{
        .file_writer = &stderr_writer,
        // The UEFI text console doesn't interpret ANSI escapes, so never
        // claim `.escape_codes`; `.no_color` turns `Terminal.setColor` into
        // a no-op. (Color via SetAttribute would need a custom Terminal mode,
        // which `std.Io.Terminal.Mode` doesn't allow for.)
        .terminal_mode = terminal_mode orelse .no_color,
    };
}

pub fn tryLockStderr(userdata: ?*anyopaque, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!?Io.LockedStderr {
    // Single-threaded: the lock can always be taken (recursively).
    return try lockStderr(userdata, terminal_mode);
}

pub fn unlockStderr(_: ?*anyopaque) void {
    // Mirrors `Io.Threaded.unlockStderr`: the lock owns the final flush, and
    // the caller-provided buffer must not be left installed after release.
    if (stderr_writer.err == null) stderr_writer.interface.flush() catch {};
    stderr_writer.err = null;
    stderr_writer.interface.end = 0;
    stderr_writer.interface.buffer = &.{};
    stderr_lock_count -= 1;
}
