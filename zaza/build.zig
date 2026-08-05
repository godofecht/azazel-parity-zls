const std = @import("std");
// zls's Uri consumed through the standard Zig build graph Zaza is built on.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const uri = b.createModule(.{ .root_source_file = b.path("vendor/Uri.zig"), .target = target, .optimize = optimize });
    const exe = b.addExecutable(.{ .name = "uri_consumer", .root_module = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize }) });
    exe.root_module.addImport("uri", uri);
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    b.step("run", "Build the Uri consumer and run it").dependOn(&run.step);
}
