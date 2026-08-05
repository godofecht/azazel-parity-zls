//! Zig 0.14 / 0.15 / 0.16 filesystem divergences in one place, matching the
//! adaptor zaza uses. Zig 0.16 moved the filesystem under `std.Io` and threads
//! an `Io` handle through every call. Each helper takes an `io` that is a real
//! `Io` on 0.16 and an ignored `void` on the older versions; only the branch
//! for the running compiler is analysed.

const std = @import("std");

/// True only on Zig 0.16, where filesystem calls take an `Io`.
pub const has_io = !@hasDecl(std.fs, "cwd");

/// A process-wide `Io` for standalone programs. On 0.14 and 0.15 this is a
/// `void` the helpers ignore.
pub fn io() if (has_io) std.Io else void {
    if (comptime has_io) return std.Io.Threaded.global_single_threaded.io();
    return {};
}

/// Whether a path exists and is accessible, relative to the current directory.
pub fn exists(ioh: anytype, path: []const u8) bool {
    if (comptime has_io) {
        std.Io.Dir.cwd().access(ioh, path, .{}) catch return false;
    } else {
        std.fs.cwd().access(path, .{}) catch return false;
    }
    return true;
}

/// Read a whole file relative to the current directory, or null on error.
pub fn readFile(ioh: anytype, alloc: std.mem.Allocator, path: []const u8) ?[]u8 {
    if (comptime has_io) {
        return std.Io.Dir.cwd().readFileAlloc(ioh, path, alloc, .unlimited) catch null;
    } else {
        return std.fs.cwd().readFileAlloc(alloc, path, 64 * 1024 * 1024) catch null;
    }
}

test "exists through the adaptor" {
    const ioh = io();
    try std.testing.expect(exists(ioh, "schema.cue"));
    try std.testing.expect(!exists(ioh, "definitely-not-a-real-file.xyz"));
}
