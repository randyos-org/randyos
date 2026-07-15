//! A `std.Io` implementation backed by UEFI protocols.
//!
//! Zig's standard library routes `std.debug.print`, the default panic
//! handler, and `std.log`'s default logFn through the `Io` instance named by
//! `std.Options.debug_io`. The default implementation (`std.Io.Threaded`)
//! doesn't compile for UEFI targets (it needs a POSIX/Windows syscall layer),
//! so this directory provides a replacement built on what UEFI firmware
//! actually offers, and the bootloader root exports it as
//! `std_options_debug_io`. With that hook in place `std.debug.print`, the
//! panic handler, and (via `rstd.logging.logFn`) `std.log` all work, and the
//! loader reads the kernel image through ordinary `std.Io` file calls.
//!
//! The `Io.VTable` has no optional fields, so every entry must be populated
//! even though most have no UEFI equivalent (processes, networking...).
//! What's implemented for real:
//!
//! * `lockStderr`/`tryLockStderr`/`unlockStderr` -- Simple Text Output
//!   Protocol (`con_out`), the path `std.debug.print`/`std.log`/panic use.
//! * `dirOpenFile`/`fileReadPositional`/`fileLength`/`fileClose`/`dirClose`
//!   -- the Simple File System protocol on the boot volume (see
//!   `openRootDir`). At most ONE directory (the volume root) and ONE file
//!   can be open at a time: `Io.Dir`/`Io.File` carry no handle bits on UEFI
//!   targets (`posix.fd_t` is `void`), so distinct open files would be
//!   indistinguishable -- see state.zig.
//! * `now`/`clockResolution` -- `RuntimeServices.getTime()` for `.real`
//!   (whole-second RTC), the `time.zig` tick counter for everything else.
//! * `sleep` -- `BootServices.stall()`.
//! * `random`/`randomSecure` -- the EFI RNG protocol, with a timer-seeded
//!   PRNG fallback for the infallible `random`.
//! * `async`/`groupAsync` -- run the task eagerly on the calling "thread",
//!   which is valid (and the only option) in a single-threaded environment.
//! * Cancellation/futex primitives -- no-ops; there is exactly one task, so
//!   nothing can ever cancel or wake it. Returning immediately from a futex
//!   wait is a legal spurious wakeup.
//!
//! Everything else panics with the name of the missing operation. That's a
//! feature: if std ever grows a dependency on an operation we haven't
//! considered, we want a loud named failure, not silent garbage.
//!
//! Boot Services lifetime: call `init()` early (it wires up `con_out` and the
//! tick clock) and `stop()` right after `exitBootServices()` -- after that
//! point console output is silently dropped and stall/RNG calls degrade to
//! no-ops, because the protocols backing them no longer exist.

const sysinfo = @import("builtin");
const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;

const log = std.log.scoped(.bootio);

const time = @import("time.zig");
const state = @import("state.zig");
const stderr = @import("stderr.zig");
const random = @import("random.zig");
const dir = @import("dir.zig");
const net = @import("net.zig");
const file = @import("file.zig");
const progress = @import("progress.zig");
const async = @import("async.zig");
const proc = @import("proc.zig");

const native_os = sysinfo.os.tag;
const is_windows = native_os == .windows;
const is_darwin = native_os.isDarwin();
const is_debug = sysinfo.mode == .Debug;

pub fn unsupported(comptime src: std.builtin.SourceLocation) noreturn {
    @panic("std.Io." ++ src.fn_name ++ " is not available in the UEFI boot environment");
}

pub const init = state.init;
pub const stop = state.stop;
pub const openRootDir = dir.openRootDir;

/// Statically initialize such that calls to `Io.VTable.concurrent` will fail
/// with `error.ConcurrencyUnavailable`.
///
/// When initialized this way:
/// * cancel requests have no effect.
/// * `deinit` is safe, but unnecessary to call.
pub const init_single_threaded: Io.Threaded = init: {
    const env_block: std.process.Environ.Block = if (is_windows) .global else .empty;
    break :init .{
        .allocator = .failing,
        .stack_size = std.Thread.SpawnConfig.default_stack_size,
        .async_limit = .nothing,
        .cpu_count_error = null,
        .concurrent_limit = .nothing,
        .old_sig_io = undefined,
        .old_sig_pipe = undefined,
        .have_signal_handler = false,
        .argv0 = .empty,
        .environ_initialized = env_block.isEmpty(),
        .environ = .{ .process_environ = .{ .block = env_block } },
        .worker_threads = .init(null),
        .disable_memory_mapping = false,
    };
};

var global_single_threaded_instance: Io.Threaded = .init_single_threaded;

/// In general, the application is responsible for choosing the `Io`
/// implementation and library code should accept an `Io` parameter rather than
/// accessing this declaration. Most code should avoid referencing this
/// declaration entirely.
///
/// However, in some cases such as debugging, it is desirable to hardcode a
/// reference to this `Io` implementation.
///
/// This instance does not support concurrency or cancelation.
pub const global_single_threaded: *Io.Threaded = &global_single_threaded_instance;

pub const Threaded: Io.Threaded = .{};

/// The `Io` instance to export from the root module as
/// `std_options_debug_io`. All state lives in this file's globals rather
/// than `userdata` because UEFI gives us exactly one console, one clock,
/// and one task -- there is nothing to instantiate twice.
pub fn io(t: *std.Io.Threaded) std.Io {
    return .{
        .userdata = t,
        .vtable = &.{
            .crashHandler = async.crashHandler,
            .async = async.async,
            .concurrent = async.concurrent,
            .await = async.await,
            .cancel = async.cancel,
            .groupAsync = async.groupAsync,
            .groupConcurrent = async.groupConcurrent,
            .groupAwait = async.groupAwait,
            .groupCancel = async.groupCancel,
            .recancel = async.recancel,
            .swapCancelProtection = async.swapCancelProtection,
            .checkCancel = async.checkCancel,
            .futexWait = async.futexWait,
            .futexWaitUncancelable = async.futexWaitUncancelable,
            .futexWake = async.futexWake,
            .operate = async.operate,
            .batchAwaitAsync = async.batchAwaitAsync,
            .batchAwaitConcurrent = async.batchAwaitConcurrent,
            .batchCancel = async.batchCancel,

            .dirCreateDir = dir.dirCreateDir,
            .dirCreateDirPath = dir.dirCreateDirPath,
            .dirCreateDirPathOpen = dir.dirCreateDirPathOpen,
            .dirOpenDir = dir.dirOpenDir,
            .dirStat = dir.dirStat,
            .dirStatFile = dir.dirStatFile,
            .dirAccess = dir.dirAccess,
            .dirCreateFile = dir.dirCreateFile,
            .dirCreateFileAtomic = dir.dirCreateFileAtomic,
            .dirOpenFile = dir.dirOpenFile,
            .dirClose = dir.dirClose,
            .dirRead = dir.dirRead,
            .dirRealPath = dir.dirRealPath,
            .dirRealPathFile = dir.dirRealPathFile,
            .dirDeleteFile = dir.dirDeleteFile,
            .dirDeleteDir = dir.dirDeleteDir,
            .dirRename = dir.dirRename,
            .dirRenamePreserve = dir.dirRenamePreserve,
            .dirSymLink = dir.dirSymLink,
            .dirReadLink = dir.dirReadLink,
            .dirSetOwner = dir.dirSetOwner,
            .dirSetFileOwner = dir.dirSetFileOwner,
            .dirSetPermissions = dir.dirSetPermissions,
            .dirSetFilePermissions = dir.dirSetFilePermissions,
            .dirSetTimestamps = dir.dirSetTimestamps,
            .dirHardLink = dir.dirHardLink,

            .fileStat = file.fileStat,
            .fileLength = file.fileLength,
            .fileClose = file.fileClose,
            .fileWritePositional = file.fileWritePositional,
            .fileWriteFileStreaming = file.fileWriteFileStreaming,
            .fileWriteFilePositional = file.fileWriteFilePositional,
            .fileReadPositional = file.fileReadPositional,
            .fileSeekBy = file.fileSeekBy,
            .fileSeekTo = file.fileSeekTo,
            .fileSync = file.fileSync,
            .fileIsTty = file.fileIsTty,
            .fileEnableAnsiEscapeCodes = file.fileEnableAnsiEscapeCodes,
            .fileSupportsAnsiEscapeCodes = file.fileSupportsAnsiEscapeCodes,
            .fileSetLength = file.fileSetLength,
            .fileSetOwner = file.fileSetOwner,
            .fileSetPermissions = file.fileSetPermissions,
            .fileSetTimestamps = file.fileSetTimestamps,
            .fileLock = file.fileLock,
            .fileTryLock = file.fileTryLock,
            .fileUnlock = file.fileUnlock,
            .fileDowngradeLock = file.fileDowngradeLock,
            .fileRealPath = file.fileRealPath,
            .fileHardLink = file.fileHardLink,

            .fileMemoryMapCreate = file.fileMemoryMapCreate,
            .fileMemoryMapDestroy = file.fileMemoryMapDestroy,
            .fileMemoryMapSetLength = file.fileMemoryMapSetLength,
            .fileMemoryMapRead = file.fileMemoryMapRead,
            .fileMemoryMapWrite = file.fileMemoryMapWrite,

            .processExecutableOpen = proc.processExecutableOpen,
            .processExecutablePath = proc.processExecutablePath,
            .lockStderr = stderr.lockStderr,
            .tryLockStderr = stderr.tryLockStderr,
            .unlockStderr = stderr.unlockStderr,
            .processCurrentPath = proc.processCurrentPath,
            .processSetCurrentDir = proc.processSetCurrentDir,
            .processSetCurrentPath = proc.processSetCurrentPath,
            .processReplace = proc.processReplace,
            .processReplacePath = proc.processReplacePath,
            .processSpawn = proc.processSpawn,
            .processSpawnPath = proc.processSpawnPath,
            .childWait = proc.childWait,
            .childKill = proc.childKill,

            .progressParentFile = progress.progressParentFile,

            .now = time.now,
            .clockResolution = time.clockResolution,
            .sleep = time.sleep,

            .random = random.random,
            .randomSecure = random.randomSecure,

            .netListenIp = net.netListenIp,
            .netAccept = net.netAccept,
            .netBindIp = net.netBindIp,
            .netConnectIp = net.netConnectIp,
            .netListenUnix = net.netListenUnix,
            .netConnectUnix = net.netConnectUnix,
            .netSocketCreatePair = net.netSocketCreatePair,
            .netSend = net.netSend,
            .netWrite = net.netWrite,
            .netWriteFile = net.netWriteFile,
            .netClose = net.netClose,
            .netShutdown = net.netShutdown,
            .netInterfaceNameResolve = net.netInterfaceNameResolve,
            .netInterfaceName = net.netInterfaceName,
            .netLookup = net.netLookup,
        },
    };
}
