const std = @import("std");

pub fn fileExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch {
        return false;
    };
    return true;
}
