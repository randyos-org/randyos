const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;

const state = @import("state.zig");

/// Write bytes to UEFI console as UCS-2, expand "\n" -> "\r\n" (LF doesn't
/// return column). Assumes ASCII -- no UTF-8 decoding, multi-byte chars break.
///
/// `stderrDrain` only gets `*Io.Writer`, not `Threaded` userdata, so this
/// reaches console via global singleton directly -- only one console anyway
/// (see state.zig).
fn putsConsole(bytes: []const u8) void {
    const out = state.con_out orelse return;
    // batched: outputString is a firmware call, one per char would be slow
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

/// `Io.Writer.VTable` backing `Threaded.stderr_writer` (see state.zig).
/// `file_writer` must point at Io.File.Writer but never touches `.file` --
/// writes go through `.interface`, this vtable. state.zig's `File` is a
/// dummy; `stderrDrain` does the real work.
pub const stderr_writer_vtable: Io.Writer.VTable = .{
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

pub fn lockStderr(userdata: ?*anyopaque, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!Io.LockedStderr {
    const t: *Io.Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    state.stderr_lock_count += 1;
    return .{
        .file_writer = &state.stderr_writer,
        // UEFI console has no ANSI escapes; `.no_color` no-ops setColor.
        // (SetAttribute color needs a custom Terminal mode, not supported)
        .terminal_mode = terminal_mode orelse .no_color,
    };
}

pub fn tryLockStderr(userdata: ?*anyopaque, terminal_mode: ?Io.Terminal.Mode) Io.Cancelable!?Io.LockedStderr {
    // single-threaded: lock always available (recursively)
    return try lockStderr(userdata, terminal_mode);
}

pub fn unlockStderr(userdata: ?*anyopaque) void {
    const t: *Io.Threaded = @ptrCast(@alignCast(userdata));
    _ = t;
    // mirrors Io.Threaded.unlockStderr: lock owns final flush, clear caller buffer
    if (state.stderr_writer.err == null) state.stderr_writer.interface.flush() catch {};
    state.stderr_writer.err = null;
    state.stderr_writer.interface.end = 0;
    state.stderr_writer.interface.buffer = &.{};
    state.stderr_lock_count -= 1;
}
