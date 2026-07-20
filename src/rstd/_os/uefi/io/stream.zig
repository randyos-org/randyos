const std = @import("std");
const Io = std.Io;

pub const stdout = std.Io.File.stdout;
pub const stderr = std.Io.File.stderr;
pub const stdin = std.Io.File.stdin;

// pub fn stdout() Io.File {
//     return .{
//         .handle = std.posix.STDOUT_FILENO,
//         .flags = .{ .nonblocking = false },
//     };
// }

// pub fn stderr() Io.File {
//     return .{
//         .handle = std.posix.STDERR_FILENO,
//         .flags = .{ .nonblocking = false },
//     };
// }

// pub fn stdin() Io.File {
//     return .{
//         .handle = std.posix.STDIN_FILENO,
//         .flags = .{ .nonblocking = false },
//     };
// }
