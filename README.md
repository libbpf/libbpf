
This is a mirror of [bpf-next linux tree](https://kernel.googlesource.com/pub/scm/linux/kernel/git/bpf/bpf-next)'s
`tools/lib/bpf` directory plus its supporting header files.

The following files will by sync'ed with bpf-next repo:
  - `src/` <-> `bpf-next/tools/lib/bpf/`
  - `include/uapi/linux/bpf_common.h` <-> `bpf-next/tools/include/uapi/linux/bpf_common.h`
  - `include/uapi/linux/bpf.h` <-> `bpf-next/tools/include/uapi/linux/bpf.h`
  - `include/uapi/linux/btf.h` <-> `bpf-next/tools/include/uapi/linux/btf.h`
  - `include/uapi/linux/if_link.h` <-> `bpf-next/tools/include/uapi/linux/if_link.h`
  - `include/uapi/linux/if_xdp.h` <-> `bpf-next/tools/include/uapi/linux/if_xdp.h`
  - `include/uapi/linux/netlink.h` <-> `bpf-next/tools/include/uapi/linux/netlink.h`
  - `include/tools/libc_compat.h` <-> `bpf-next/tools/include/tools/libc_compat.h`

Other header files at this repo (`include/linux/*.h`) are reduced versions of
their counterpart files at bpf-next's `tools/include/linux/*.h` to make compilation
successful.

Build
[![Build Status](https://travis-ci.org/libbpf/libbpf.svg?branch=master)](https://travis-ci.org/libbpf/libbpf)
[![Total alerts](https://img.shields.io/lgtm/alerts/g/libbpf/libbpf.svg?logo=lgtm&logoWidth=18)](https://lgtm.com/projects/g/libbpf/libbpf/alerts/)
[![Coverity](https://img.shields.io/coverity/scan/18195.svg)](https://scan.coverity.com/projects/libbpf)
=====
libelf is an internal dependency of libbpf and thus it is required to link
against and must be installed on the system for applications to work.
pkg-config is used by default to find libelf, and the program called can be
overridden with `PKG_CONFIG`.
If using `pkg-config` at build time is not desired, it can be disabled by setting
`NO_PKG_CONFIG=1` when calling make.

To build both static libbpf.a and shared libbpf.so:
```bash
$ cd src
$ make
```

To build only static libbpf.a library in directory
build/ and install them together with libbpf headers in a staging directory
root/:
```bash
$ cd src
$ mkdir build root
$ BUILD_STATIC_ONLY=y OBJDIR=build DESTDIR=root make install
```

To build both static libbpf.a and shared libbpf.so against a custom libelf
dependency installed in /build/root/ and install them together with libbpf
headers in a build directory /build/root/:
```bash
$ cd src
$ PKG_CONFIG_PATH=/build/root/lib64/pkgconfig DESTDIR=/build/root make install
```

Distributions
=============

Distributions packaging libbpf from this mirror:
  - [Fedora](https://src.fedoraproject.org/rpms/libbpf)
  - [Gentoo](https://packages.gentoo.org/packages/dev-libs/libbpf)
  - [Debian](https://packages.debian.org/sid/libbpf-dev)

Benefits of packaging from the mirror over packaging from kernel sources:
  - Consistent versioning across distributions.
  - No ties to any specific kernel, transparent handling of older kernels.
    Libbpf is designed to be kernel-agnostic and work across multitude of kernel
    versions. It has built-in mechanisms to gracefully handle older kernels,
    that are missing some of the features, by working around or gracefully
    degrading functionality. Thus libbpf is not tied to a specific kernel
    version and can/should be packaged and versioned independently.
  - Continuous integration testing via [TravisCI](https://travis-ci.org/libbpf/libbpf).
  - Static code analysis via [LGTM](https://lgtm.com/projects/g/libbpf/libbpf) and [Coverity](https://scan.coverity.com/projects/libbpf).

Package dependencies of libbpf, package names may vary across distros:
  - zlib
  - libelf

BPF CO-RE (Compile Once – Run Everywhere)
=========================================

Libbpf supports building BPF CO-RE-enabled applications, which, in contrast to
[BCC](https://github.com/iovisor/bcc/), do not require Clang/LLVM runtime
being deployed to target servers and doesn't rely on kernel-devel headers
being available.

It does rely on kernel to be built with [BTF type
information](https://www.kernel.org/doc/html/latest/bpf/btf.html), though.
Some major Linux distributions come with kernel BTF already built in:
  - Fedora 31+
  - RHEL 8.2+
  - OpenSUSE Tumbleweed (in the next release, as of 2020-06-04)
  - Arch Linux (from kernel 5.7.1.arch1-1)

If your kernel doesn't come with BTF built-in, you'll need to build custom
kernel. You'll need:
  - `pahole` 1.16+ tool (part of `dwarves` package), which performs DWARF to
    BTF conversion;
  - kernel built with `CONFIG_DEBUG_INFO_BTF=y` option;
  - you can check if your kernel has BTF built-in by looking for
    `/sys/kernel/btf/vmlinux` file:
  
```shell
$ ls -la /sys/kernel/btf/vmlinux
-r--r--r--. 1 root root 3541561 Jun  2 18:16 /sys/kernel/btf/vmlinux
```
  
To develop and build BPF programs, you'll need Clang/LLVM 10+. The following
distributions have Clang/LLVM 10+ packaged by default:
  - Fedora 32+
  - Ubuntu 20.04+
  - Arch Linux

Otherwise, please make sure to update it on your system.

The following resources are useful to understand what BPF CO-RE is and how to
use it:
- [BPF Portability and CO-RE](https://facebookmicrosites.github.io/bpf/blog/2020/02/19/bpf-portability-and-co-re.html)
- [HOWTO: BCC to libbpf conversion](https://facebookmicrosites.github.io/bpf/blog/2020/02/20/bcc-to-libbpf-howto-guide.html)
- [libbpf-tools in BCC repo](https://github.com/iovisor/bcc/tree/master/libbpf-tools)
  contain lots of real-world tools converted from BCC to BPF CO-RE. Consider
  converting some more to both contribute to the BPF community and gain some
  more experience with it.

License
=======

This work is dual-licensed under BSD 2-clause license and GNU LGPL v2.1 license.
You can choose between one of them if you use this work.

`SPDX-License-Identifier: BSD-2-Clause OR LGPL-2.1`
