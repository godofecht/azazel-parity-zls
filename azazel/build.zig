const std = @import("std");
const spec = @import("build_spec.zig");
const builtin = @import("builtin");

fn laneMatchesCurrent(comptime lane: []const u8) bool {
    if (std.mem.eql(u8, lane, "0.14")) {
        return builtin.zig_version.major == 0 and builtin.zig_version.minor == 14;
    }
    if (std.mem.eql(u8, lane, "0.15")) {
        return builtin.zig_version.major == 0 and builtin.zig_version.minor == 15;
    }
    if (std.mem.eql(u8, lane, "0.16")) {
        return builtin.zig_version.major == 0 and builtin.zig_version.minor == 16;
    }
    if (std.mem.eql(u8, lane, "0.17")) {
        return builtin.zig_version.major == 0 and builtin.zig_version.minor == 17;
    }
    return false;
}

fn supportsCurrentZig() bool {
    inline for (spec.toolchain.zig_lanes) |lane| {
        if (laneMatchesCurrent(lane)) return true;
    }
    return false;
}

comptime {
    if (!supportsCurrentZig()) {
        @compileError("unsupported Zig toolchain lane for this Azazel build spec; regenerate or run with a Zig lane declared in project.cue toolchain.zig.lanes");
    }
}

fn linkOf(name: []const u8) spec.Link {
    for (spec.modules) |m| {
        if (std.mem.eql(u8, m.name, name)) return m.link;
    }
    return .abi;
}

fn kindOf(name: []const u8) spec.Kind {
    for (spec.modules) |m| {
        if (std.mem.eql(u8, m.name, name)) return m.kind;
    }
    return .module;
}

fn addPostCommand(b: *std.Build, module_name: []const u8, index: usize, cmd: spec.Command) *std.Build.Step {
    const run = b.addSystemCommand(cmd.argv);
    run.stdio = .inherit;
    const step = b.step(
        b.fmt("{s}-post-{d}", .{ module_name, index }),
        b.fmt("Run post-build command {d} for {s}", .{ index, module_name }),
    );
    step.dependOn(&run.step);
    return step;
}

fn addCommand(b: *std.Build, module_name: []const u8, phase: []const u8, index: usize, cmd: spec.Command) *std.Build.Step {
    const run = b.addSystemCommand(cmd.argv);
    run.stdio = .inherit;
    const step = b.step(
        b.fmt("{s}-{s}-{d}", .{ module_name, phase, index }),
        b.fmt("Run {s} command {d} for {s}", .{ phase, index, module_name }),
    );
    step.dependOn(&run.step);
    return step;
}

fn installDir(name: []const u8) std.Build.InstallDir {
    if (std.mem.eql(u8, name, "bin")) return .bin;
    if (std.mem.eql(u8, name, "lib")) return .lib;
    if (std.mem.eql(u8, name, "header")) return .header;
    return .{ .custom = name };
}

fn targetOsMatches(filter: ?[]const u8, target: std.Target) bool {
    const os = filter orelse return true;
    if (std.mem.eql(u8, os, "macos")) return target.os.tag == .macos;
    if (std.mem.eql(u8, os, "linux")) return target.os.tag == .linux;
    if (std.mem.eql(u8, os, "windows")) return target.os.tag == .windows;
    if (std.mem.eql(u8, os, "emscripten")) return target.os.tag == .emscripten;
    return false;
}

fn targetArchMatches(filter: ?[]const u8, target: std.Target) bool {
    const arch = filter orelse return true;
    if (std.mem.eql(u8, arch, "aarch64")) return target.cpu.arch.isAARCH64();
    if (std.mem.eql(u8, arch, "x86_64")) return target.cpu.arch == .x86_64;
    if (std.mem.eql(u8, arch, "x86")) return target.cpu.arch.isX86();
    if (std.mem.eql(u8, arch, "wasm32")) return target.cpu.arch == .wasm32;
    return false;
}

fn applyPackageLibraryPaths(
    b: *std.Build,
    step: *std.Build.Step.Compile,
    paths: []const spec.PackageLibraryPath,
    target: std.Target,
) void {
    for (paths) |path| {
        if (!targetOsMatches(path.os, target)) continue;
        if (!targetArchMatches(path.arch, target)) continue;
        const dep = b.lazyDependency(path.package, .{}) orelse @panic("package library path dependency unavailable");
        step.root_module.addLibraryPath(dep.path(path.path));
    }
}

fn findOption(name: []const u8) ?spec.Option {
    for (spec.options) |option| {
        if (std.mem.eql(u8, option.name, name)) return option;
    }
    return null;
}

fn addBuildOptions(
    b: *std.Build,
    module_name: []const u8,
    option_names: []const []const u8,
    option_values: []const spec.OptionValue,
) ?*std.Build.Step.Options {
    if (option_names.len == 0 and option_values.len == 0) return null;

    const options = b.addOptions();
    for (option_names) |name| {
        const option = findOption(name) orelse @panic("module references unknown build option");
        switch (option.type) {
            .bool => {
                const value = b.option(bool, option.name, option.description) orelse (option.bool_default orelse false);
                options.addOption(bool, option.name, value);
            },
            .string => {
                const value = b.option([]const u8, option.name, option.description) orelse (option.string_default orelse "");
                options.addOption([]const u8, option.name, value);
            },
            .u32 => {
                const value = b.option(u32, option.name, option.description) orelse (option.u32_default orelse 0);
                options.addOption(u32, option.name, value);
            },
        }
    }

    // Injected literal values, for options modules a repo's build.zig would
    // normally synthesize (e.g. tigerbeetle's vsr_options).
    for (option_values) |ov| {
        if (std.mem.eql(u8, ov.kind, "bool")) {
            options.addOption(bool, ov.name, ov.bool_value);
        } else if (std.mem.eql(u8, ov.kind, "string")) {
            options.addOption([]const u8, ov.name, ov.string_value);
        } else if (std.mem.eql(u8, ov.kind, "u32")) {
            options.addOption(u32, ov.name, ov.u32_value);
        } else if (std.mem.eql(u8, ov.kind, "opt_commit")) {
            // A ?[40]u8 git commit hash: the 40-char value, or null.
            if (ov.commit_value) |commit| {
                var buf: [40]u8 = undefined;
                if (commit.len != 40) @panic("opt_commit value must be exactly 40 characters");
                @memcpy(&buf, commit[0..40]);
                options.addOption(?[40]u8, ov.name, buf);
            } else {
                options.addOption(?[40]u8, ov.name, null);
            }
        } else {
            @panic("unsupported option_value kind");
        }
    }

    _ = module_name;
    return options;
}

fn generatedModule(b: *std.Build, gen: spec.GeneratedImport) *std.Build.Module {
    // Compile the repo's host tool, run it, and turn the file it writes into a
    // module. The tool builds for the host (it runs at build time), and the run
    // captures each output file's path from the build graph so the emitted file
    // is a real dependency, not a fixed path on disk.
    const tool = b.addExecutable(.{
        .name = gen.tool_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path(gen.tool_root),
            .target = b.graph.host,
            .single_threaded = true,
        }),
    });

    const run = b.addRunArtifact(tool);
    var output_path: ?std.Build.LazyPath = null;
    for (gen.args) |arg| {
        if (std.mem.eql(u8, arg.kind, "literal")) {
            run.addArg(arg.value);
        } else if (std.mem.eql(u8, arg.kind, "input_file")) {
            run.addFileArg(b.path(arg.value));
        } else if (std.mem.eql(u8, arg.kind, "output_file")) {
            const path = run.addOutputFileArg(arg.value);
            if (std.mem.eql(u8, arg.value, gen.output)) output_path = path;
        } else {
            @panic("unsupported generated-import arg kind");
        }
    }

    return b.createModule(.{
        .root_source_file = output_path orelse @panic("generated import names no output_file matching `output`"),
    });
}

fn applyNative(b: *std.Build, mod: *std.Build.Module, native: spec.Native) void {
    if (native.link_libc) mod.link_libc = true;
    if (native.link_libcpp) mod.link_libcpp = true;

    for (native.c_sources) |src| {
        mod.addCSourceFile(.{ .file = b.path(src), .flags = &.{} });
    }
    for (native.include_dirs) |dir| {
        mod.addIncludePath(b.path(dir));
    }
    for (native.system_include_dirs) |dir| {
        mod.addSystemIncludePath(b.path(dir));
    }
    for (native.library_paths) |dir| {
        mod.addLibraryPath(b.path(dir));
    }
    for (native.object_files) |file| {
        mod.addObjectFile(b.path(file));
    }
    for (native.system_libs) |lib| {
        mod.linkSystemLibrary(lib, .{});
    }
    for (native.pkg_config_libs) |lib| {
        mod.linkSystemLibrary(lib, .{ .use_pkg_config = .force });
    }
    for (native.frameworks) |framework| {
        mod.linkFramework(framework, .{});
    }
}

fn dependencyWithoutBackend(
    b: *std.Build,
    package: []const u8,
    pass_target: bool,
    pass_optimize: bool,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Dependency {
    if (pass_target and pass_optimize) {
        return b.dependency(package, .{
            .target = target,
            .optimize = optimize,
        });
    }
    if (pass_target) {
        return b.dependency(package, .{
            .target = target,
        });
    }
    if (pass_optimize) {
        return b.dependency(package, .{
            .optimize = optimize,
        });
    }
    return b.dependency(package, .{});
}

fn dependencyWithBackend(
    b: *std.Build,
    package: []const u8,
    pass_target: bool,
    pass_optimize: bool,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime backend: anytype,
) *std.Build.Dependency {
    if (pass_target and pass_optimize) {
        return b.dependency(package, .{
            .target = target,
            .optimize = optimize,
            .backend = backend,
        });
    }
    if (pass_target) {
        return b.dependency(package, .{
            .target = target,
            .backend = backend,
        });
    }
    if (pass_optimize) {
        return b.dependency(package, .{
            .optimize = optimize,
            .backend = backend,
        });
    }
    return b.dependency(package, .{
        .backend = backend,
    });
}

fn dependencyWithOptions(
    b: *std.Build,
    package: []const u8,
    pass_target: bool,
    pass_optimize: bool,
    backend: ?[]const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Dependency {
    const backend_name = backend orelse return dependencyWithoutBackend(b, package, pass_target, pass_optimize, target, optimize);

    if (std.mem.eql(u8, backend_name, "no_backend")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .no_backend);
    if (std.mem.eql(u8, backend_name, "glfw_wgpu")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .glfw_wgpu);
    if (std.mem.eql(u8, backend_name, "glfw_opengl3")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .glfw_opengl3);
    if (std.mem.eql(u8, backend_name, "glfw_vulkan")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .glfw_vulkan);
    if (std.mem.eql(u8, backend_name, "glfw_dx12")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .glfw_dx12);
    if (std.mem.eql(u8, backend_name, "win32_dx12")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .win32_dx12);
    if (std.mem.eql(u8, backend_name, "glfw")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .glfw);
    if (std.mem.eql(u8, backend_name, "sdl2_opengl3")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .sdl2_opengl3);
    if (std.mem.eql(u8, backend_name, "osx_metal")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .osx_metal);
    if (std.mem.eql(u8, backend_name, "sdl2")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .sdl2);
    if (std.mem.eql(u8, backend_name, "sdl2_renderer")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .sdl2_renderer);
    if (std.mem.eql(u8, backend_name, "sdl3")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .sdl3);
    if (std.mem.eql(u8, backend_name, "sdl3_opengl3")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .sdl3_opengl3);
    if (std.mem.eql(u8, backend_name, "sdl3_vulkan")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .sdl3_vulkan);
    if (std.mem.eql(u8, backend_name, "sdl3_renderer")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .sdl3_renderer);
    if (std.mem.eql(u8, backend_name, "sdl3_gpu")) return dependencyWithBackend(b, package, pass_target, pass_optimize, target, optimize, .sdl3_gpu);

    @panic("unsupported package dependency backend");
}

fn dependencyWithFields(
    b: *std.Build,
    package: []const u8,
    pass_target: bool,
    pass_optimize: bool,
    fields: []const []const u8,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Dependency {
    if (pass_target and pass_optimize) {
        return b.dependency(package, .{
            .target = target,
            .optimize = optimize,
            .fields = fields,
        });
    }
    if (pass_target) {
        return b.dependency(package, .{
            .target = target,
            .fields = fields,
        });
    }
    if (pass_optimize) {
        return b.dependency(package, .{
            .optimize = optimize,
            .fields = fields,
        });
    }
    return b.dependency(package, .{
        .fields = fields,
    });
}

fn dependencyForImport(
    b: *std.Build,
    pkg_import: spec.PackageImport,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Dependency {
    // A `fields` string-list option (e.g. uucode's Unicode property tables) is
    // passed alongside target/optimize. It is mutually exclusive with `backend`
    // in practice: no corpus dependency takes both.
    if (pkg_import.fields.len > 0) {
        return dependencyWithFields(
            b,
            pkg_import.package,
            pkg_import.pass_target,
            pkg_import.pass_optimize,
            pkg_import.fields,
            target,
            optimize,
        );
    }
    return dependencyWithOptions(
        b,
        pkg_import.package,
        pkg_import.pass_target,
        pkg_import.pass_optimize,
        pkg_import.backend,
        target,
        optimize,
    );
}

fn dependencyForArtifact(
    b: *std.Build,
    pkg_artifact: spec.PackageArtifact,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) *std.Build.Dependency {
    return dependencyWithOptions(
        b,
        pkg_artifact.package,
        pkg_artifact.pass_target,
        pkg_artifact.pass_optimize,
        pkg_artifact.backend,
        target,
        optimize,
    );
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // A Zig module for every declared module, and a compile step only for the
    // ones that become a real artifact. An `import` dependency is merged into
    // its dependents as a module, so it needs no artifact and no link step.
    var modules = std.StringHashMap(*std.Build.Module).init(b.allocator);
    var steps = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator);
    defer modules.deinit();
    defer steps.deinit();

    for (spec.modules) |m| {
        // Zig 0.15 takes target and optimize on the module rather than on the
        // compile step, and folds addStaticLibrary/addSharedLibrary into
        // addLibrary with an explicit linkage.
        const mod = b.createModule(.{
            .root_source_file = b.path(m.root),
            .target = target,
            .optimize = m.optimize,
        });
        applyNative(b, mod, m.native);
        if (addBuildOptions(b, m.name, m.build_options, m.option_values)) |options| {
            mod.addOptions(m.build_options_import, options);
        }
        modules.put(m.name, mod) catch unreachable;
    }

    for (spec.modules) |m| {
        const mod = modules.get(m.name).?;
        for (m.pkg_imports) |pkg_import| {
            const dep = dependencyForImport(b, pkg_import, target, m.optimize);
            mod.addImport(pkg_import.alias, dep.module(pkg_import.module));
        }
        for (m.pkg_artifacts) |pkg_artifact| {
            const dep = dependencyForArtifact(b, pkg_artifact, target, m.optimize);
            mod.linkLibrary(dep.artifact(pkg_artifact.artifact));
        }
        for (m.gen_imports) |gen| {
            mod.addImport(gen.alias, generatedModule(b, gen));
        }
    }

    for (spec.modules) |m| {
        // Executables and shared libraries are always artifacts. A static
        // library is an artifact only when it is linked over the ABI; an
        // `import` static module compiles inside its dependents.
        const needs_artifact = switch (m.kind) {
            .exe, .shared => true,
            .static => m.link == .abi,
            .module => false,
        };
        if (!needs_artifact) continue;

        const mod = modules.get(m.name).?;
        // The module map stays keyed by the module name (the graph and @import
        // name). Only the produced artifact takes artifact_name, which defaults
        // to the module name when the project does not override it.
        const step = switch (m.kind) {
            .exe => b.addExecutable(.{
                .name = m.artifact_name,
                .root_module = mod,
            }),
            .static => b.addLibrary(.{
                .name = m.artifact_name,
                .root_module = mod,
                .linkage = .static,
            }),
            .shared => b.addLibrary(.{
                .name = m.artifact_name,
                .root_module = mod,
                .linkage = .dynamic,
            }),
            .module => unreachable,
        };
        for (m.pre, 0..) |cmd, idx| {
            const pre = addCommand(b, m.name, "pre", idx, cmd);
            step.step.dependOn(pre);
        }
        for (m.install_dirs) |dir| {
            const install_dir = b.addInstallDirectory(.{
                .source_dir = b.path(dir.source_dir),
                .install_dir = installDir(dir.install_dir),
                .install_subdir = dir.install_subdir,
            });
            step.step.dependOn(&install_dir.step);
            b.getInstallStep().dependOn(&install_dir.step);
        }
        applyPackageLibraryPaths(b, step, m.pkg_library_paths, target.result);
        steps.put(m.name, step) catch unreachable;
    }

    for (spec.modules) |m| {
        const mod = modules.get(m.name).?;
        for (m.deps) |dep| {
            if (linkOf(dep) == .import and (kindOf(dep) == .static or kindOf(dep) == .module)) {
                // Merge the dependency into this compilation. Its source is
                // reached with `@import("<name>")`.
                mod.addImport(dep, modules.get(dep).?);
            } else {
                // 0.16 moved linkLibrary from Compile onto Module. Module.linkLibrary
                // exists in 0.14 and 0.15 too, so this spelling works on all three.
                mod.linkLibrary(steps.get(dep).?);
            }
        }
    }

    for (spec.modules) |m| {
        if (steps.get(m.name)) |step| {
            const install = b.addInstallArtifact(step, .{});
            b.getInstallStep().dependOn(&install.step);
            for (m.post, 0..) |cmd, idx| {
                const post = addPostCommand(b, m.name, idx, cmd);
                post.dependOn(&install.step);
                b.getInstallStep().dependOn(post);
            }
        }
    }

    // --- tests ---
    //
    // Three suites: the build-spec invariants that build.zig above relies on,
    // the small src/ helpers, and the vendored danzig core.
    const test_step = b.step("test", "Run all tests");

    const suites = [_][]const u8{
        "compat.zig",
        "build_spec_test.zig",
        "src/core_test.zig",
        "src/danzig/tests.zig",
    };

    for (suites) |suite| {
        const t = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(suite),
                .target = target,
                .optimize = .Debug,
            }),
        });
        const run_t = b.addRunArtifact(t);
        // build_spec_test reads module roots off disk, so run from the repo root.
        run_t.setCwd(b.path("."));
        test_step.dependOn(&run_t.step);
    }
}
