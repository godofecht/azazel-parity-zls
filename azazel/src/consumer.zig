//! Consumer of zls's Uri: parses a URL and prints the normalized raw
//! string, forcing zls's URI parse/normalize logic to compile and run.
const std = @import("std");
const Uri = @import("uri");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const u = try Uri.parse(arena.allocator(), "https://example.com/a/../b");
    std.debug.print("zls uri: raw={s}\n", .{u.raw});
}
