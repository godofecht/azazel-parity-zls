// Azazel builds a consumer of zls's Uri (a self-contained std-only URI
// parse/normalize module), declared as a CUE model, on the 0.17 lane (zls's
// real toolchain). Source staged by ./fetch.sh into vendor/ (git-ignored).
package build

toolchain: zig: {
	lanes: ["0.17"]
	preferred: "0.17"
}

uri: #Module & {
	kind: "module"
	root: "vendor/Uri.zig"
}

consumer: #Module & {
	kind: "exe"
	root: "src/consumer.zig"
	deps: ["uri"]
}
