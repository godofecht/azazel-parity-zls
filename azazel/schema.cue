package build

#Kind:    "exe" | "static" | "shared" | "module"
#Profile: "debug" | "release"
#ZigLane: "0.14" | "0.15" | "0.16" | "0.17"
#OptionType: "bool" | "string" | "u32"

// How a module is consumed by the things that depend on it.
//
//   abi    a separately compiled artifact linked over the C ABI. Symbols cross
//          the edge as `pub export fn` / `extern fn`. Required for shared
//          libraries and for any C or C++ interop.
//   import merged into each dependent as a plain Zig module, reached with
//          `@import("<name>")`. One compilation, no link step. Much faster to
//          rebuild, and the only sensible choice for pure Zig-to-Zig edges.
//
// Default is `abi` so existing projects build unchanged.
#Link: "abi" | "import"

#Command: {
	argv: [...string]
}

#InstallDir: {
	source_dir: string
	install_dir: string | *"bin"
	install_subdir: string
}

#PackageLibraryPath: {
	package: string
	path: string | *""
	os?: string
	arch?: string
}

#PackageImport: {
	alias:   string
	package: string
	module:  string
	pass_target: bool | *true
	pass_optimize: bool | *true
	backend?: string

	// A `fields` string-list option passed to the dependency, for packages
	// that select which data tables to compile in (e.g. uucode's Unicode
	// property fields). Emitted as `.fields = @as([]const []const u8, ...)`
	// only when non-empty, so ordinary imports are unaffected.
	fields: [...string] | *[]
}

#PackageArtifact: {
	package: string
	artifact: string
	pass_target: bool | *true
	pass_optimize: bool | *true
	backend?: string
}

// A literal, typed value injected into a module's build-options module (the
// one imported under build_options_import). Unlike #Option, which surfaces a
// CLI flag, an #OptionValue is a fixed value the build config supplies so a
// module that does @import("<options>") compiles without the project's own
// build.zig. Used to reproduce generated options like tigerbeetle's
// vsr_options. `kind` selects which typed field is emitted.
#OptionValue: {
	name: string
	kind: "bool" | "string" | "u32" | "opt_commit"
	bool_value:   bool | *false
	string_value: string | *""
	u32_value:    uint32 | *0
	// opt_commit emits a ?[40]u8: a 40-char hex string, or "" for null.
	commit: string | *""
}

#Package: {
	url?: string
	hash?: string
	path?: string
	lazy: bool | *false
}

// One argument to a generated module's host tool. `literal` is passed verbatim;
// `input_file` is a repo path passed as a build-graph file dependency (so the
// run reruns when it changes); `output_file` names a file the tool writes,
// whose path the build graph captures.
#GenArg: {
	kind:  "literal" | "input_file" | "output_file"
	value: string
}

// A module produced by compiling a host tool from the repo, running it, and
// importing the file it writes. This reproduces a repo's codegen step (e.g.
// zls compiles src/tools/config_gen.zig, runs it, and imports the emitted
// version_data.zig as a module) without invoking the repo's own build.zig.
#GeneratedImport: {
	alias:     string   // @import name the consuming module uses
	tool_root: string   // host tool source (.zig), built for the host
	tool_name: string   // produced host executable's name
	args: [...#GenArg]
	output:    string   // the output_file arg whose written file is the module root
}

#Option: {
	name: string
	type: #OptionType
	description: string | *""
	default?: bool | string | int
}

#Native: {
	c_sources: [...string] | *[]
	include_dirs: [...string] | *[]
	system_include_dirs: [...string] | *[]
	library_paths: [...string] | *[]
	object_files: [...string] | *[]
	system_libs: [...string] | *[]
	pkg_config_libs: [...string] | *[]
	frameworks: [...string] | *[]
	link_libc: bool | *false
	link_libcpp: bool | *false
}

#Module: {
	kind:     #Kind
	root:     string

	// The produced artifact's name. Defaults to the module key. Set it when the
	// built exe or library should carry a name distinct from the module's graph
	// and `@import` name, e.g. a static `lib:xev` alongside a `module:xev`
	// import that both compile from one project.
	artifact_name?: string

	deps: [...string] | *[]
	profile:  #Profile | *"debug"
	link:     #Link | *"abi"
	post: [...#Command] | *[]
	pre: [...#Command] | *[]
	install_dirs: [...#InstallDir] | *[]
	pkg_library_paths: [...#PackageLibraryPath] | *[]
	pkg_imports: [...#PackageImport] | *[]
	pkg_artifacts: [...#PackageArtifact] | *[]
	build_options: [...string] | *[]
	option_values: [...#OptionValue] | *[]
	gen_imports: [...#GeneratedImport] | *[]
	build_options_import: string | *"build-options"
	native: #Native | *{}

	// A shared library is an ABI artifact by definition.
	if kind == "shared" {
		link: "abi"
	}

	// A module-only target has no artifact to link, so dependents consume it as
	// an import.
	if kind == "module" {
		link: "import"
	}
}

#Profiles: {
	debug: {
		optimize: "Debug"
	}
	release: {
		optimize: "ReleaseFast"
	}
}

#Toolchain: {
	zig: {
		// Azazel is maintained as explicit Zig API lanes. A project can narrow
		// this list when it relies on one lane's std.Build surface.
		lanes: [...#ZigLane] | *["0.14", "0.15", "0.16"]
		preferred: #ZigLane | *"0.15"
	}
}

profiles: #Profiles
toolchain: #Toolchain | *{}
packages: [string]: #Package | *{}
options: [...#Option] | *[]
