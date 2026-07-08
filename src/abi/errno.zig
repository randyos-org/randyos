//! Linux errno values, generic across x86_64, arm, and arm64.
//!
//! Sourced from the Linux kernel source tree (`include/uapi/asm-generic/errno-base.h`
//! for values 1-34 and `include/uapi/asm-generic/errno.h` for values 35+),
//! torvalds/linux @ 8cdeaa50eae8dad34885515f62559ee83e7e8dda (kernel version 7.2.0-rc2), by fetching
//! those files directly and mechanically extracting (name, value) pairs -- not
//! transcribed by hand. Re-derive from those same files if this ever looks
//! stale; do not hand-edit numbers here.
//!
//! `arch/x86/include/uapi/asm/errno.h`, `arch/arm/include/uapi/asm/errno.h`,
//! and `arch/arm64/include/uapi/asm/errno.h` do not exist at this commit --
//! all three of those architectures use this generic numbering verbatim.
//! `arch/powerpc/include/uapi/asm/errno.h` DOES override one value; see the
//! `EDEADLOCK_powerpc` note below.
//!
//! Some names in the generic C headers are aliases (`#define`d to another
//! name's value rather than a distinct number). Since a Zig enum cannot have
//! two members share one value without `EnumField` duplication headaches,
//! aliases are instead exposed as `pub const` bindings to the canonical
//! `Number` member, immediately below the enum.
//!
//! Not wired to any dispatcher -- this is a numbering reference only.

const std = @import("std");
const log = std.log.scoped(.abi_errno);

pub const Number = enum(u16) {
    /// Operation not permitted: the caller lacks the privilege to perform
    /// the requested action.
    EPERM = 1,
    /// No such file or directory: a path component or target does not exist.
    ENOENT = 2,
    /// No such process: the referenced process ID does not exist.
    ESRCH = 3,
    /// Interrupted system call: a signal arrived while blocked in a
    /// system call, aborting it before completion.
    EINTR = 4,
    /// I/O error: a low-level input/output error occurred on the device.
    EIO = 5,
    /// No such device or address: the device/address does not exist or is
    /// out of range for the device.
    ENXIO = 6,
    /// Argument list too long: the exec argument/environment list exceeds
    /// the system limit.
    E2BIG = 7,
    /// Exec format error: the executable file has an invalid or
    /// unsupported binary format.
    ENOEXEC = 8,
    /// Bad file number: the file descriptor is not open or is invalid.
    EBADF = 9,
    /// No child processes: `wait`-family call found no child to wait for.
    ECHILD = 10,
    /// Try again: the resource is temporarily unavailable; retry later.
    EAGAIN = 11,
    /// Out of memory: the kernel could not allocate the memory needed for
    /// the operation.
    ENOMEM = 12,
    /// Permission denied: access to the resource is denied by file mode
    /// or capability checks.
    EACCES = 13,
    /// Bad address: an invalid pointer was passed for a memory access
    /// argument.
    EFAULT = 14,
    /// Block device required: a block-special device was expected but
    /// something else was given.
    ENOTBLK = 15,
    /// Device or resource busy: the resource is in use and cannot be
    /// modified or removed right now.
    EBUSY = 16,
    /// File exists: the target of a creation call already exists.
    EEXIST = 17,
    /// Cross-device link: an operation (e.g. rename/link) would need to
    /// cross filesystem/device boundaries, which is not allowed.
    EXDEV = 18,
    /// No such device: the requested device does not exist.
    ENODEV = 19,
    /// Not a directory: a path component expected to be a directory
    /// isn't one.
    ENOTDIR = 20,
    /// Is a directory: an operation that requires a non-directory was
    /// given a directory.
    EISDIR = 21,
    /// Invalid argument: one or more arguments to the call are not valid.
    EINVAL = 22,
    /// File table overflow: the system-wide open file table is full.
    ENFILE = 23,
    /// Too many open files: the per-process open file descriptor limit
    /// was reached.
    EMFILE = 24,
    /// Not a typewriter: an ioctl/terminal operation was attempted on a
    /// file that is not a terminal device.
    ENOTTY = 25,
    /// Text file busy: attempted to write to an executable that is
    /// currently being run.
    ETXTBSY = 26,
    /// File too large: the file exceeds the maximum allowed size.
    EFBIG = 27,
    /// No space left on device: the filesystem/device has no free space.
    ENOSPC = 28,
    /// Illegal seek: a seek was attempted on a file that does not
    /// support seeking (e.g. a pipe).
    ESPIPE = 29,
    /// Read-only file system: a write was attempted on a filesystem
    /// mounted read-only.
    EROFS = 30,
    /// Too many links: the maximum number of hard links to a file was
    /// exceeded.
    EMLINK = 31,
    /// Broken pipe: wrote to a pipe or socket whose reading end is
    /// closed.
    EPIPE = 32,
    /// Math argument out of domain of function: a math function was
    /// called with an argument outside its valid domain.
    EDOM = 33,
    /// Math result not representable: a math function's result cannot be
    /// represented in the destination type (overflow/underflow).
    ERANGE = 34,
    /// Resource deadlock would occur: acquiring the requested lock would
    /// deadlock the caller.
    EDEADLK = 35,
    /// File name too long: a path or path component exceeds the maximum
    /// allowed length.
    ENAMETOOLONG = 36,
    /// No record locks available: the system has run out of resources
    /// for file record locks.
    ENOLCK = 37,
    /// Invalid system call number: the requested syscall does not exist
    /// (kernel/arch code returns this for unimplemented syscall numbers).
    ENOSYS = 38,
    /// Directory not empty: a directory removal/rename target still
    /// contains entries.
    ENOTEMPTY = 39,
    /// Too many symbolic links encountered: path resolution exceeded the
    /// maximum symlink nesting depth (likely a symlink loop).
    ELOOP = 40,
    /// No message of desired type: no message matching the requested type
    /// is available on the message queue.
    ENOMSG = 42,
    /// Identifier removed: the IPC identifier (semaphore, message queue,
    /// etc.) has been removed.
    EIDRM = 43,
    /// Channel number out of range: an STREAMS/multiplexed-channel number
    /// is outside the valid range.
    ECHRNG = 44,
    /// Level 2 not synchronized: the STREAMS data link layer is not
    /// synchronized.
    EL2NSYNC = 45,
    /// Level 3 halted: the STREAMS network layer has halted.
    EL3HLT = 46,
    /// Level 3 reset: the STREAMS network layer has reset.
    EL3RST = 47,
    /// Link number out of range: a STREAMS link number is outside the
    /// valid range.
    ELNRNG = 48,
    /// Protocol driver not attached: no protocol driver is attached to
    /// the STREAMS device.
    EUNATCH = 49,
    /// No CSI structure available: no STREAMS control structure is
    /// available for the request.
    ENOCSI = 50,
    /// Level 2 halted: the STREAMS data link layer has halted.
    EL2HLT = 51,
    /// Invalid exchange: an X.25 (or similar) exchange identifier is
    /// invalid.
    EBADE = 52,
    /// Invalid request descriptor: a request descriptor for an exchange
    /// is invalid.
    EBADR = 53,
    /// Exchange full: an X.25-style exchange has no room for more
    /// requests.
    EXFULL = 54,
    /// No anode: the kernel ran out of internal "anode" resources.
    ENOANO = 55,
    /// Invalid request code: the request code sent to an exchange is
    /// invalid.
    EBADRQC = 56,
    /// Invalid slot: the slot number given to an exchange is invalid.
    EBADSLT = 57,
    /// Bad font file format: a console/framebuffer font file is
    /// malformed.
    EBFONT = 59,
    /// Device not a stream: an operation requiring a STREAMS device was
    /// used on a non-STREAMS file.
    ENOSTR = 60,
    /// No data available: a STREAMS read found no data currently
    /// queued.
    ENODATA = 61,
    /// Timer expired: a STREAMS timeout expired before completion.
    ETIME = 62,
    /// Out of streams resources: the system ran out of STREAMS
    /// resources.
    ENOSR = 63,
    /// Machine is not on the network: the local host is not currently
    /// attached to the network.
    ENONET = 64,
    /// Package not installed: an optional kernel package/module needed
    /// for this operation is not installed.
    ENOPKG = 65,
    /// Object is remote: the object being operated on resides on a
    /// remote system.
    EREMOTE = 66,
    /// Link has been severed: the communication link to a remote
    /// resource was cut.
    ENOLINK = 67,
    /// Advertise error: an XNS/STREAMS advertise operation failed.
    EADV = 68,
    /// Srmount error: a "srmount" (shared resource mount) operation
    /// failed.
    ESRMNT = 69,
    /// Communication error on send: an error occurred while sending data
    /// over a communication link.
    ECOMM = 70,
    /// Protocol error: a low-level protocol violation occurred.
    EPROTO = 71,
    /// Multihop attempted: the operation would require multiple hops,
    /// which is not permitted.
    EMULTIHOP = 72,
    /// RFS specific error: an error specific to the Remote File Sharing
    /// (RFS) protocol occurred.
    EDOTDOT = 73,
    /// Not a data message: the message received is not a data message
    /// (e.g. it is a control message).
    EBADMSG = 74,
    /// Value too large for defined data type: a value doesn't fit in the
    /// type used to represent it (e.g. a large file offset on a 32-bit
    /// type).
    EOVERFLOW = 75,
    /// Name not unique on network: the requested name already exists
    /// elsewhere on the network.
    ENOTUNIQ = 76,
    /// File descriptor in bad state: the descriptor is open but in a
    /// state that makes the operation invalid.
    EBADFD = 77,
    /// Remote address changed: the address of a remote peer changed
    /// unexpectedly.
    EREMCHG = 78,
    /// Can not access a needed shared library: a required shared library
    /// could not be opened.
    ELIBACC = 79,
    /// Accessing a corrupted shared library: a shared library file is
    /// corrupted.
    ELIBBAD = 80,
    /// .lib section in a.out corrupted: the `.lib` section of an a.out
    /// binary is corrupted.
    ELIBSCN = 81,
    /// Attempting to link in too many shared libraries: the maximum
    /// number of linked shared libraries was exceeded.
    ELIBMAX = 82,
    /// Cannot exec a shared library directly: a shared library was passed
    /// to `exec` as if it were a standalone executable.
    ELIBEXEC = 83,
    /// Illegal byte sequence: invalid multibyte/wide-character data was
    /// encountered.
    EILSEQ = 84,
    /// Interrupted system call should be restarted: internal marker
    /// telling the kernel to automatically restart the system call.
    ERESTART = 85,
    /// Streams pipe error: an error occurred in a STREAMS-based pipe.
    ESTRPIPE = 86,
    /// Too many users: the maximum number of simultaneous users for a
    /// resource (e.g. a filesystem) was exceeded.
    EUSERS = 87,
    /// Socket operation on non-socket: a socket call was made on a file
    /// descriptor that is not a socket.
    ENOTSOCK = 88,
    /// Destination address required: the socket operation needs a
    /// destination address but none was supplied.
    EDESTADDRREQ = 89,
    /// Message too long: a datagram was larger than the maximum the
    /// transport allows and had to be discarded/truncated.
    EMSGSIZE = 90,
    /// Protocol wrong type for socket: the specified protocol does not
    /// support the given socket type.
    EPROTOTYPE = 91,
    /// Protocol not available: the requested socket option/protocol is
    /// not available.
    ENOPROTOOPT = 92,
    /// Protocol not supported: the protocol is not supported by this
    /// address family.
    EPROTONOSUPPORT = 93,
    /// Socket type not supported: the socket type is not supported by
    /// this protocol family.
    ESOCKTNOSUPPORT = 94,
    /// Operation not supported on transport endpoint: the requested
    /// operation isn't supported by this socket/endpoint.
    EOPNOTSUPP = 95,
    /// Protocol family not supported: the address/protocol family is not
    /// supported.
    EPFNOSUPPORT = 96,
    /// Address family not supported by protocol: the address family is
    /// incompatible with the chosen protocol.
    EAFNOSUPPORT = 97,
    /// Address already in use: the requested local address is already
    /// bound by another socket.
    EADDRINUSE = 98,
    /// Cannot assign requested address: the requested local address is
    /// not available on this host.
    EADDRNOTAVAIL = 99,
    /// Network is down: the local network is currently unreachable/down.
    ENETDOWN = 100,
    /// Network is unreachable: no route exists to the destination
    /// network.
    ENETUNREACH = 101,
    /// Network dropped connection because of reset: the connection was
    /// reset by the network (e.g. due to a host crash/reboot).
    ENETRESET = 102,
    /// Software caused connection abort: the local host aborted the
    /// connection.
    ECONNABORTED = 103,
    /// Connection reset by peer: the remote host forcibly closed the
    /// connection.
    ECONNRESET = 104,
    /// No buffer space available: the kernel could not allocate enough
    /// buffer space for the socket operation.
    ENOBUFS = 105,
    /// Transport endpoint is already connected: a `connect` was attempted
    /// on a socket that is already connected.
    EISCONN = 106,
    /// Transport endpoint is not connected: the socket needs to be
    /// connected before this operation but isn't.
    ENOTCONN = 107,
    /// Cannot send after transport endpoint shutdown: data was sent
    /// after `shutdown` disabled sends on the socket.
    ESHUTDOWN = 108,
    /// Too many references: cannot splice: too many file descriptor
    /// references would need to be duplicated (e.g. during `sendmsg` of
    /// an fd array).
    ETOOMANYREFS = 109,
    /// Connection timed out: no response was received from the peer
    /// within the allowed time.
    ETIMEDOUT = 110,
    /// Connection refused: the remote host actively refused the
    /// connection (e.g. no listener on that port).
    ECONNREFUSED = 111,
    /// Host is down: the remote host is currently down/unreachable.
    EHOSTDOWN = 112,
    /// No route to host: no network route exists to the remote host.
    EHOSTUNREACH = 113,
    /// Operation already in progress: a non-blocking operation on this
    /// socket is already in progress.
    EALREADY = 114,
    /// Operation now in progress: a non-blocking operation was started
    /// and has not completed yet.
    EINPROGRESS = 115,
    /// Stale file handle: the remote (e.g. NFS) file handle no longer
    /// refers to a valid file.
    ESTALE = 116,
    /// Structure needs cleaning: an on-disk structure is inconsistent and
    /// needs repair (e.g. filesystem corruption).
    EUCLEAN = 117,
    /// Not a XENIX named type file: expected a XENIX special named-type
    /// file.
    ENOTNAM = 118,
    /// No XENIX semaphores available: the system has no XENIX-style
    /// semaphores left.
    ENAVAIL = 119,
    /// Is a named type file: the file is a XENIX named-type special
    /// file.
    EISNAM = 120,
    /// Remote I/O error: an I/O error occurred on a remote
    /// filesystem/device.
    EREMOTEIO = 121,
    /// Quota exceeded: the user/group disk quota has been exceeded.
    EDQUOT = 122,
    /// No medium found: no removable medium (e.g. disc) is present in
    /// the drive.
    ENOMEDIUM = 123,
    /// Wrong medium type: the inserted medium is of the wrong type for
    /// this operation.
    EMEDIUMTYPE = 124,
    /// Operation canceled: the asynchronous operation was canceled
    /// before it completed.
    ECANCELED = 125,
    /// Required key not available: the requested kernel key does not
    /// exist or is inaccessible.
    ENOKEY = 126,
    /// Key has expired: the kernel key's validity period has ended.
    EKEYEXPIRED = 127,
    /// Key has been revoked: the kernel key was explicitly revoked.
    EKEYREVOKED = 128,
    /// Key was rejected by service: the key was rejected by the
    /// requesting service (e.g. authentication failure).
    EKEYREJECTED = 129,
    /// Owner died: the previous owner of a robust mutex died while
    /// holding it, leaving it in an inconsistent state.
    EOWNERDEAD = 130,
    /// State not recoverable: a robust mutex/state is unrecoverable after
    /// its owner died.
    ENOTRECOVERABLE = 131,
    /// Operation not possible due to RF-kill: the operation is blocked
    /// because the relevant radio has been RF-killed (disabled).
    ERFKILL = 132,
    /// Memory page has hardware error: the memory page contains an
    /// uncorrectable hardware error (e.g. a machine-check poisoned page).
    EHWPOISON = 133,
    /// Wrong file type for the intended operation: the file's type is
    /// not appropriate for what was requested.
    EFTYPE = 134,
};

/// `#define EWOULDBLOCK EAGAIN` in `include/uapi/asm-generic/errno.h`.
///
/// Operation would block: the non-blocking call cannot complete right now
/// and would otherwise have to wait.
pub const EWOULDBLOCK = Number.EAGAIN;

/// `#define EDEADLOCK EDEADLK` in `include/uapi/asm-generic/errno.h`.
///
/// Resource deadlock would occur: acquiring the requested lock would
/// deadlock the caller.
///
/// This is the generic (x86_64 / arm / arm64) binding. See
/// `EDEADLOCK_powerpc` below for the powerpc-specific override.
pub const EDEADLOCK = Number.EDEADLK;

/// `#define EFSBADCRC EBADMSG` in `include/uapi/asm-generic/errno.h`.
///
/// Bad CRC detected: a filesystem block failed its checksum
/// verification.
pub const EFSBADCRC = Number.EBADMSG;

/// `#define EFSCORRUPTED EUCLEAN` in `include/uapi/asm-generic/errno.h`.
///
/// Filesystem is corrupted: an on-disk filesystem structure is
/// inconsistent and needs repair.
pub const EFSCORRUPTED = Number.EUCLEAN;

/// powerpc-specific override: `arch/powerpc/include/uapi/asm/errno.h` does
/// `#undef EDEADLOCK` (discarding the generic `EDEADLOCK == EDEADLK` alias
/// pulled in via `#include <asm-generic/errno.h>`) and then re-`#define`s
/// `EDEADLOCK` to the distinct literal value `58`, which is otherwise unused
/// in the generic numbering. On powerpc only, `EDEADLOCK` is therefore its
/// own errno value, NOT an alias for `EDEADLK` (35). Do not use `Number`'s
/// `EDEADLOCK` alias (`Number.EDEADLK`) when targeting powerpc; use this
/// constant instead.
///
/// Meaning is the same as generic `EDEADLK`/`EDEADLOCK`: resource deadlock
/// would occur.
pub const EDEADLOCK_powerpc: u16 = 58;
