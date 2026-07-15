const std = @import("std");
const uefi = std.os.uefi;
const Io = std.Io;
const log = std.log.scoped(.random);

const state = @import("state.zig");
const time = @import("time.zig");

/// Outer optional distinguishes "never looked" from "looked and absent":
/// locateProtocol is a firmware call, so only do it once.
var rng_lookup: ??*uefi.protocol.Rng = null;

fn locateRng() ?*uefi.protocol.Rng {
    if (rng_lookup == null) {
        const bs = state.bootServices() orelse return null;
        rng_lookup = bs.locateProtocol(uefi.protocol.Rng, null) catch null;
    }
    return rng_lookup.?;
}

pub fn randomSecure(_: ?*anyopaque, buffer: []u8) Io.RandomSecureError!void {
    const rng = locateRng() orelse return error.EntropyUnavailable;
    rng.getRNG(null, buffer) catch return error.EntropyUnavailable;
}

/// Fallback for `random` when the firmware has no RNG protocol; seeded from
/// the tick clock on first use. Not cryptographically secure -- callers who
/// need that use `randomSecure`, which fails honestly instead.
var fallback_prng: ?std.Random.DefaultPrng = null;

pub fn random(_: ?*anyopaque, buffer: []u8) void {
    randomSecure(null, buffer) catch {
        if (fallback_prng == null) {
            var seed: u64 = time.getElapsedNanoseconds();
            // The stack address adds a little per-boot variety on firmware
            // where the timer hasn't started yet (seed would otherwise be 0).
            seed ^= @intFromPtr(&seed) *% 0x9e3779b97f4a7c15;
            fallback_prng = .init(seed);
        }
        fallback_prng.?.fill(buffer);
    };
}
