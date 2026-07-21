const std = @import("std");
const linux = std.os.linux;

// pub const ARCH = linux.arch_bits.ARCH;
// pub const SC = linux.arch_bits.SC;
// pub const VDSO = linux.arch_bits.VDSO;
// pub const user_desc = linux.arch_bits.user_desc;
// pub const time_t = linux.arch_bits.time_t;

// pub const blkcnt_t = u64;
// pub const blksize_t = u32;
// pub const dev_t = u32;
// pub const ino_t = u64;
// pub const mode_t = u32;
// pub const nlink_t = u32;
// pub const off_t = i64;
// pub const pid_t = i32;
// pub const fd_t = i32;
// pub const socket_t = fd_t;
// pub const uid_t = u32;
// pub const gid_t = u32;
// pub const clock_t = isize;

pub const NAME_MAX = 255;
pub const PATH_MAX = 4096;
pub const IOV_MAX = 1024;

/// Largest hardware address length
/// e.g. a mac address is a type of hardware address
pub const MAX_ADDR_LEN = 32;

pub const STDIN_FILENO = 0;
pub const STDOUT_FILENO = 1;
pub const STDERR_FILENO = 2;
