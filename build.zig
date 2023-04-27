//! Requires zig version: 0.11 or higher (w/ pkg-manager)

const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{
        .whitelist = permissive_targets,
    });

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "bpf",
        .target = target,
        .optimize = optimize,
    });
    if (optimize == .Debug or optimize == .ReleaseSafe)
        lib.bundle_compiler_rt = true
    else
        lib.strip = true;
    lib.addIncludePath("src");
    lib.addIncludePath("include");
    lib.addIncludePath("include/uapi");
    lib.addCSourceFiles(src, &.{
        "-Wall",
        "-Wextra",
    });
    lib.defineCMacro("_LARGEFILE64_SOURCE", null);
    lib.defineCMacro("_FILE_OFFSET_BITS", "64");
    lib.linkSystemLibrary("elf");
    lib.linkSystemLibrary("z");
    lib.linkLibC();
    // copy all headers to zig-out/include
    lib.installHeadersDirectory("include", "");
    lib.installHeadersDirectoryOptions(.{
        .source_dir = "src",
        .install_dir = .header,
        .install_subdir = "",
        .exclude_extensions = &.{
            "c",
            "Makefile",
            "map",
            "template",
        },
    });
    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(lib);
}

const src = &.{
    "src/btf.c",
    "src/btf_dump.c",
    "src/usdt.c",
    "src/libbpf_errno.c",
    "src/linker.c",
    "src/relo_core.c",
    "src/str_error.c",
    "src/libbpf.c",
    "src/bpf_prog_linfo.c",
    "src/hashmap.c",
    "src/libbpf_probes.c",
    "src/bpf.c",
    "src/zip.c",
    "src/netlink.c",
    "src/gen_loader.c",
    "src/ringbuf.c",
    "src/strset.c",
    "src/nlattr.c",
};

const permissive_targets: []const std.zig.CrossTarget = &.{
    .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .gnu,
    },
    .{
        .cpu_arch = .x86,
        .os_tag = .linux,
        .abi = .gnu,
    },
    .{
        .cpu_arch = .x86_64,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .x86,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .gnu,
    },
    .{
        .cpu_arch = .aarch64,
        .os_tag = .linux,
        .abi = .musl,
    },
    // .{
    //     .cpu_arch = .riscv64,
    //     .os_tag = .linux,
    //     .abi = .gnu,
    // https://github.com/ziglang/zig/issues/3340
    // },
    .{
        .cpu_arch = .riscv64,
        .os_tag = .linux,
        .abi = .musl,
    },
    .{
        .cpu_arch = .powerpc64,
        .os_tag = .linux,
        .abi = .gnu,
    },
    .{
        .cpu_arch = .powerpc64,
        .os_tag = .linux,
        .abi = .musl,
    },
};
// see all targets list:
// run: zig targets | jq .libc (json format)
