/* SPDX-License-Identifier: (LGPL-2.1 OR BSD-2-Clause) */

/*
 * Common eBPF ELF object loading operations.
 *
 * Copyright (C) 2013-2015 Alexei Starovoitov <ast@kernel.org>
 * Copyright (C) 2015 Wang Nan <wangnan0@huawei.com>
 * Copyright (C) 2015 Huawei Inc.
 */
#ifndef __LIBBPF_LIBBPF_H
#define __LIBBPF_LIBBPF_H

#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <sys/types.h>  // for size_t
#include <linux/bpf.h>

#include "libbpf_common.h"
#include "libbpf_legacy.h"

#ifdef __cplusplus
extern "C" {
#endif

LIBBPF_API __u32 libbpf_major_version(void);
LIBBPF_API __u32 libbpf_minor_version(void);
LIBBPF_API const char *libbpf_version_string(void);

enum libbpf_errno {
	__LIBBPF_ERRNO__START = 4000,

	/* Something wrong in libelf */
	LIBBPF_ERRNO__LIBELF = __LIBBPF_ERRNO__START,
	LIBBPF_ERRNO__FORMAT,	/* BPF object format invalid */
	LIBBPF_ERRNO__KVERSION,	/* Incorrect or no 'version' section */
	LIBBPF_ERRNO__ENDIAN,	/* Endian mismatch */
	LIBBPF_ERRNO__INTERNAL,	/* Internal error in libbpf */
	LIBBPF_ERRNO__RELOC,	/* Relocation failed */
	LIBBPF_ERRNO__LOAD,	/* Load program failure for unknown reason */
	LIBBPF_ERRNO__VERIFY,	/* Kernel verifier blocks program loading */
	LIBBPF_ERRNO__PROG2BIG,	/* Program too big */
	LIBBPF_ERRNO__KVER,	/* Incorrect kernel version */
	LIBBPF_ERRNO__PROGTYPE,	/* Kernel doesn't support this program type */
	LIBBPF_ERRNO__WRNGPID,	/* Wrong pid in netlink message */
	LIBBPF_ERRNO__INVSEQ,	/* Invalid netlink sequence */
	LIBBPF_ERRNO__NLPARSE,	/* netlink parsing error */
	__LIBBPF_ERRNO__END,
};

LIBBPF_API int libbpf_strerror(int err, char *buf, size_t size);

enum libbpf_print_level {
        LIBBPF_WARN,
        LIBBPF_INFO,
        LIBBPF_DEBUG,
};

typedef int (*libbpf_print_fn_t)(enum libbpf_print_level level,
				 const char *, va_list ap);

LIBBPF_API libbpf_print_fn_t libbpf_set_print(libbpf_print_fn_t fn);

/* Hide internal to user */
struct bpf_object;

struct bpf_object_open_attr {
	const char *file;
	enum bpf_prog_type prog_type;
};

struct bpf_object_open_opts {
	/* size of this struct, for forward/backward compatiblity */
	size_t sz;
	/* object name override, if provided:
	 * - for object open from file, this will override setting object
	 *   name from file path's base name;
	 * - for object open from memory buffer, this will specify an object
	 *   name and will override default "<addr>-<buf-size>" name;
	 */
	const char *object_name;
	/* parse map definitions non-strictly, allowing extra attributes/data */
	bool relaxed_maps;
	/* DEPRECATED: handle CO-RE relocations non-strictly, allowing failures.
	 * Value is ignored. Relocations always are processed non-strictly.
	 * Non-relocatable instructions are replaced with invalid ones to
	 * prevent accidental errors.
	 * */
	LIBBPF_DEPRECATED_SINCE(0, 6, "field has no effect")
	bool relaxed_core_relocs;
	/* maps that set the 'pinning' attribute in their definition will have
	 * their pin_path attribute set to a file in this directory, and be
	 * auto-pinned to that path on load; defaults to "/sys/fs/bpf".
	 */
	const char *pin_root_path;

	LIBBPF_DEPRECATED_SINCE(0, 7, "use bpf_program__set_attach_target() on each individual bpf_program")
	__u32 attach_prog_fd;
	/* Additional kernel config content that augments and overrides
	 * system Kconfig for CONFIG_xxx externs.
	 */
	const char *kconfig;
	/* Path to the custom BTF to be used for BPF CO-RE relocations.
	 * This custom BTF completely replaces the use of vmlinux BTF
	 * for the purpose of CO-RE relocations.
	 * NOTE: any other BPF feature (e.g., fentry/fexit programs,
	 * struct_ops, etc) will need actual kernel BTF at /sys/kernel/btf/vmlinux.
	 */
	const char *btf_custom_path;
	/* Pointer to a buffer for storing kernel logs for applicable BPF
	 * commands. Valid kernel_log_size has to be specified as well and are
	 * passed-through to bpf() syscall. Keep in mind that kernel might
	 * fail operation with -ENOSPC error if provided buffer is too small
	 * to contain entire log output.
	 * See the comment below for kernel_log_level for interaction between
	 * log_buf and log_level settings.
	 *
	 * If specified, this log buffer will be passed for:
	 *   - each BPF progral load (BPF_PROG_LOAD) attempt, unless overriden
	 *     with bpf_program__set_log() on per-program level, to get
	 *     BPF verifier log output.
	 *   - during BPF object's BTF load into kernel (BPF_BTF_LOAD) to get
	 *     BTF sanity checking log.
	 *
	 * Each BPF command (BPF_BTF_LOAD or BPF_PROG_LOAD) will overwrite
	 * previous contents, so if you need more fine-grained control, set
	 * per-program buffer with bpf_program__set_log_buf() to preserve each
	 * individual program's verification log. Keep using kernel_log_buf
	 * for BTF verification log, if necessary.
	 */
	char *kernel_log_buf;
	size_t kernel_log_size;
	/*
	 * Log level can be set independently from log buffer. Log_level=0
	 * means that libbpf will attempt loading BTF or program without any
	 * logging requested, but will retry with either its own or custom log
	 * buffer, if provided, and log_level=1 on any error.
	 * And vice versa, setting log_level>0 will request BTF or prog
	 * loading with verbose log from the first attempt (and as such also
	 * for successfully loaded BTF or program), and the actual log buffer
	 * could be either libbpf's own auto-allocated log buffer, if
	 * kernel_log_buffer is NULL, or user-provided custom kernel_log_buf.
	 * If user didn't provide custom log buffer, libbpf will emit captured
	 * logs through its print callback.
	 */
	__u32 kernel_log_level;

	size_t :0;
};
#define bpf_object_open_opts__last_field kernel_log_level

LIBBPF_API struct bpf_object *bpf_object__open(const char *path);

/**
 * @brief **bpf_object__open_file()** creates a bpf_object by opening
 * the BPF ELF object file pointed to by the passed path and loading it
 * into memory.
 * @param path BPF object file path
 * @param opts options for how to load the bpf object, this parameter is
 * optional and can be set to NULL
 * @return pointer to the new bpf_object; or NULL is returned on error,
 * error code is stored in errno
 */
LIBBPF_API struct bpf_object *
bpf_object__open_file(const char *path, const struct bpf_object_open_opts *opts);

/**
 * @brief **bpf_object__open_mem()** creates a bpf_object by reading
 * the BPF objects raw bytes from a memory buffer containing a valid
 * BPF ELF object file.
 * @param obj_buf pointer to the buffer containing ELF file bytes
 * @param obj_buf_sz number of bytes in the buffer
 * @param opts options for how to load the bpf object
 * @return pointer to the new bpf_object; or NULL is returned on error,
 * error code is stored in errno
 */
LIBBPF_API struct bpf_object *
bpf_object__open_mem(const void *obj_buf, size_t obj_buf_sz,
		     const struct bpf_object_open_opts *opts);

/* deprecated bpf_object__open variants */
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_object__open_mem() instead")
LIBBPF_API struct bpf_object *
bpf_object__open_buffer(const void *obj_buf, size_t obj_buf_sz,
			const char *name);
LIBBPF_DEPRECATED_SINCE(0, 7, "use bpf_object__open_file() instead")
LIBBPF_API struct bpf_object *
bpf_object__open_xattr(struct bpf_object_open_attr *attr);

enum libbpf_pin_type {
	LIBBPF_PIN_NONE,
	/* PIN_BY_NAME: pin maps by name (in /sys/fs/bpf by default) */
	LIBBPF_PIN_BY_NAME,
};

/* pin_maps and unpin_maps can both be called with a NULL path, in which case
 * they will use the pin_path attribute of each map (and ignore all maps that
 * don't have a pin_path set).
 */
LIBBPF_API int bpf_object__pin_maps(struct bpf_object *obj, const char *path);
LIBBPF_API int bpf_object__unpin_maps(struct bpf_object *obj,
				      const char *path);
LIBBPF_API int bpf_object__pin_programs(struct bpf_object *obj,
					const char *path);
LIBBPF_API int bpf_object__unpin_programs(struct bpf_object *obj,
					  const char *path);
LIBBPF_API int bpf_object__pin(struct bpf_object *object, const char *path);
LIBBPF_API void bpf_object__close(struct bpf_object *object);

struct bpf_object_load_attr {
	struct bpf_object *obj;
	int log_level;
	const char *target_btf_path;
};

/* Load/unload object into/from kernel */
LIBBPF_API int bpf_object__load(struct bpf_object *obj);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_object__load() instead")
LIBBPF_API int bpf_object__load_xattr(struct bpf_object_load_attr *attr);
LIBBPF_DEPRECATED_SINCE(0, 6, "bpf_object__unload() is deprecated, use bpf_object__close() instead")
LIBBPF_API int bpf_object__unload(struct bpf_object *obj);

LIBBPF_API const char *bpf_object__name(const struct bpf_object *obj);
LIBBPF_API unsigned int bpf_object__kversion(const struct bpf_object *obj);
LIBBPF_API int bpf_object__set_kversion(struct bpf_object *obj, __u32 kern_version);

struct btf;
LIBBPF_API struct btf *bpf_object__btf(const struct bpf_object *obj);
LIBBPF_API int bpf_object__btf_fd(const struct bpf_object *obj);

LIBBPF_DEPRECATED_SINCE(0, 7, "use bpf_object__find_program_by_name() instead")
LIBBPF_API struct bpf_program *
bpf_object__find_program_by_title(const struct bpf_object *obj,
				  const char *title);
LIBBPF_API struct bpf_program *
bpf_object__find_program_by_name(const struct bpf_object *obj,
				 const char *name);

LIBBPF_API LIBBPF_DEPRECATED_SINCE(0, 7, "track bpf_objects in application code instead")
struct bpf_object *bpf_object__next(struct bpf_object *prev);
#define bpf_object__for_each_safe(pos, tmp)			\
	for ((pos) = bpf_object__next(NULL),		\
		(tmp) = bpf_object__next(pos);		\
	     (pos) != NULL;				\
	     (pos) = (tmp), (tmp) = bpf_object__next(tmp))

typedef void (*bpf_object_clear_priv_t)(struct bpf_object *, void *);
LIBBPF_DEPRECATED_SINCE(0, 7, "storage via set_priv/priv is deprecated")
LIBBPF_API int bpf_object__set_priv(struct bpf_object *obj, void *priv,
				    bpf_object_clear_priv_t clear_priv);
LIBBPF_DEPRECATED_SINCE(0, 7, "storage via set_priv/priv is deprecated")
LIBBPF_API void *bpf_object__priv(const struct bpf_object *prog);

LIBBPF_API int
libbpf_prog_type_by_name(const char *name, enum bpf_prog_type *prog_type,
			 enum bpf_attach_type *expected_attach_type);
LIBBPF_API int libbpf_attach_type_by_name(const char *name,
					  enum bpf_attach_type *attach_type);
LIBBPF_API int libbpf_find_vmlinux_btf_id(const char *name,
					  enum bpf_attach_type attach_type);

/* Accessors of bpf_program */
struct bpf_program;
LIBBPF_API LIBBPF_DEPRECATED_SINCE(0, 7, "use bpf_object__next_program() instead")
struct bpf_program *bpf_program__next(struct bpf_program *prog,
				      const struct bpf_object *obj);
LIBBPF_API struct bpf_program *
bpf_object__next_program(const struct bpf_object *obj, struct bpf_program *prog);

#define bpf_object__for_each_program(pos, obj)			\
	for ((pos) = bpf_object__next_program((obj), NULL);	\
	     (pos) != NULL;					\
	     (pos) = bpf_object__next_program((obj), (pos)))

LIBBPF_API LIBBPF_DEPRECATED_SINCE(0, 7, "use bpf_object__prev_program() instead")
struct bpf_program *bpf_program__prev(struct bpf_program *prog,
				      const struct bpf_object *obj);
LIBBPF_API struct bpf_program *
bpf_object__prev_program(const struct bpf_object *obj, struct bpf_program *prog);

typedef void (*bpf_program_clear_priv_t)(struct bpf_program *, void *);

LIBBPF_DEPRECATED_SINCE(0, 7, "storage via set_priv/priv is deprecated")
LIBBPF_API int bpf_program__set_priv(struct bpf_program *prog, void *priv,
				     bpf_program_clear_priv_t clear_priv);
LIBBPF_DEPRECATED_SINCE(0, 7, "storage via set_priv/priv is deprecated")
LIBBPF_API void *bpf_program__priv(const struct bpf_program *prog);
LIBBPF_API void bpf_program__set_ifindex(struct bpf_program *prog,
					 __u32 ifindex);

LIBBPF_API const char *bpf_program__name(const struct bpf_program *prog);
LIBBPF_API const char *bpf_program__section_name(const struct bpf_program *prog);
LIBBPF_API LIBBPF_DEPRECATED("BPF program title is confusing term; please use bpf_program__section_name() instead")
const char *bpf_program__title(const struct bpf_program *prog, bool needs_copy);
LIBBPF_API bool bpf_program__autoload(const struct bpf_program *prog);
LIBBPF_API int bpf_program__set_autoload(struct bpf_program *prog, bool autoload);

/* returns program size in bytes */
LIBBPF_DEPRECATED_SINCE(0, 7, "use bpf_program__insn_cnt() instead")
LIBBPF_API size_t bpf_program__size(const struct bpf_program *prog);

struct bpf_insn;

/**
 * @brief **bpf_program__insns()** gives read-only access to BPF program's
 * underlying BPF instructions.
 * @param prog BPF program for which to return instructions
 * @return a pointer to an array of BPF instructions that belong to the
 * specified BPF program
 *
 * Returned pointer is always valid and not NULL. Number of `struct bpf_insn`
 * pointed to can be fetched using **bpf_program__insn_cnt()** API.
 *
 * Keep in mind, libbpf can modify and append/delete BPF program's
 * instructions as it processes BPF object file and prepares everything for
 * uploading into the kernel. So depending on the point in BPF object
 * lifetime, **bpf_program__insns()** can return different sets of
 * instructions. As an example, during BPF object load phase BPF program
 * instructions will be CO-RE-relocated, BPF subprograms instructions will be
 * appended, ldimm64 instructions will have FDs embedded, etc. So instructions
 * returned before **bpf_object__load()** and after it might be quite
 * different.
 */
LIBBPF_API const struct bpf_insn *bpf_program__insns(const struct bpf_program *prog);
/**
 * @brief **bpf_program__insn_cnt()** returns number of `struct bpf_insn`'s
 * that form specified BPF program.
 * @param prog BPF program for which to return number of BPF instructions
 *
 * See **bpf_program__insns()** documentation for notes on how libbpf can
 * change instructions and their count during different phases of
 * **bpf_object** lifetime.
 */
LIBBPF_API size_t bpf_program__insn_cnt(const struct bpf_program *prog);

LIBBPF_DEPRECATED_SINCE(0, 6, "use bpf_object__load() instead")
LIBBPF_API int bpf_program__load(struct bpf_program *prog, const char *license, __u32 kern_version);
LIBBPF_API int bpf_program__fd(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 7, "multi-instance bpf_program support is deprecated")
LIBBPF_API int bpf_program__pin_instance(struct bpf_program *prog,
					 const char *path,
					 int instance);
LIBBPF_DEPRECATED_SINCE(0, 7, "multi-instance bpf_program support is deprecated")
LIBBPF_API int bpf_program__unpin_instance(struct bpf_program *prog,
					   const char *path,
					   int instance);

/**
 * @brief **bpf_program__pin()** pins the BPF program to a file
 * in the BPF FS specified by a path. This increments the programs
 * reference count, allowing it to stay loaded after the process
 * which loaded it has exited.
 *
 * @param prog BPF program to pin, must already be loaded
 * @param path file path in a BPF file system
 * @return 0, on success; negative error code, otherwise
 */
LIBBPF_API int bpf_program__pin(struct bpf_program *prog, const char *path);

/**
 * @brief **bpf_program__unpin()** unpins the BPF program from a file
 * in the BPFFS specified by a path. This decrements the programs
 * reference count.
 *
 * The file pinning the BPF program can also be unlinked by a different
 * process in which case this function will return an error.
 *
 * @param prog BPF program to unpin
 * @param path file path to the pin in a BPF file system
 * @return 0, on success; negative error code, otherwise
 */
LIBBPF_API int bpf_program__unpin(struct bpf_program *prog, const char *path);
LIBBPF_API void bpf_program__unload(struct bpf_program *prog);

struct bpf_link;

LIBBPF_API struct bpf_link *bpf_link__open(const char *path);
LIBBPF_API int bpf_link__fd(const struct bpf_link *link);
LIBBPF_API const char *bpf_link__pin_path(const struct bpf_link *link);
LIBBPF_API int bpf_link__pin(struct bpf_link *link, const char *path);
LIBBPF_API int bpf_link__unpin(struct bpf_link *link);
LIBBPF_API int bpf_link__update_program(struct bpf_link *link,
					struct bpf_program *prog);
LIBBPF_API void bpf_link__disconnect(struct bpf_link *link);
LIBBPF_API int bpf_link__detach(struct bpf_link *link);
LIBBPF_API int bpf_link__destroy(struct bpf_link *link);

LIBBPF_API struct bpf_link *
bpf_program__attach(const struct bpf_program *prog);

struct bpf_perf_event_opts {
	/* size of this struct, for forward/backward compatiblity */
	size_t sz;
	/* custom user-provided value fetchable through bpf_get_attach_cookie() */
	__u64 bpf_cookie;
};
#define bpf_perf_event_opts__last_field bpf_cookie

LIBBPF_API struct bpf_link *
bpf_program__attach_perf_event(const struct bpf_program *prog, int pfd);

LIBBPF_API struct bpf_link *
bpf_program__attach_perf_event_opts(const struct bpf_program *prog, int pfd,
				    const struct bpf_perf_event_opts *opts);

struct bpf_kprobe_opts {
	/* size of this struct, for forward/backward compatiblity */
	size_t sz;
	/* custom user-provided value fetchable through bpf_get_attach_cookie() */
	__u64 bpf_cookie;
	/* function's offset to install kprobe to */
	size_t offset;
	/* kprobe is return probe */
	bool retprobe;
	size_t :0;
};
#define bpf_kprobe_opts__last_field retprobe

LIBBPF_API struct bpf_link *
bpf_program__attach_kprobe(const struct bpf_program *prog, bool retprobe,
			   const char *func_name);
LIBBPF_API struct bpf_link *
bpf_program__attach_kprobe_opts(const struct bpf_program *prog,
                                const char *func_name,
                                const struct bpf_kprobe_opts *opts);

struct bpf_uprobe_opts {
	/* size of this struct, for forward/backward compatiblity */
	size_t sz;
	/* offset of kernel reference counted USDT semaphore, added in
	 * a6ca88b241d5 ("trace_uprobe: support reference counter in fd-based uprobe")
	 */
	size_t ref_ctr_offset;
	/* custom user-provided value fetchable through bpf_get_attach_cookie() */
	__u64 bpf_cookie;
	/* uprobe is return probe, invoked at function return time */
	bool retprobe;
	size_t :0;
};
#define bpf_uprobe_opts__last_field retprobe

/**
 * @brief **bpf_program__attach_uprobe()** attaches a BPF program
 * to the userspace function which is found by binary path and
 * offset. You can optionally specify a particular proccess to attach
 * to. You can also optionally attach the program to the function
 * exit instead of entry.
 *
 * @param prog BPF program to attach
 * @param retprobe Attach to function exit
 * @param pid Process ID to attach the uprobe to, 0 for self (own process),
 * -1 for all processes
 * @param binary_path Path to binary that contains the function symbol
 * @param func_offset Offset within the binary of the function symbol
 * @return Reference to the newly created BPF link; or NULL is returned on error,
 * error code is stored in errno
 */
LIBBPF_API struct bpf_link *
bpf_program__attach_uprobe(const struct bpf_program *prog, bool retprobe,
			   pid_t pid, const char *binary_path,
			   size_t func_offset);

/**
 * @brief **bpf_program__attach_uprobe_opts()** is just like
 * bpf_program__attach_uprobe() except with a options struct
 * for various configurations.
 *
 * @param prog BPF program to attach
 * @param pid Process ID to attach the uprobe to, 0 for self (own process),
 * -1 for all processes
 * @param binary_path Path to binary that contains the function symbol
 * @param func_offset Offset within the binary of the function symbol
 * @param opts Options for altering program attachment
 * @return Reference to the newly created BPF link; or NULL is returned on error,
 * error code is stored in errno
 */
LIBBPF_API struct bpf_link *
bpf_program__attach_uprobe_opts(const struct bpf_program *prog, pid_t pid,
				const char *binary_path, size_t func_offset,
				const struct bpf_uprobe_opts *opts);

struct bpf_tracepoint_opts {
	/* size of this struct, for forward/backward compatiblity */
	size_t sz;
	/* custom user-provided value fetchable through bpf_get_attach_cookie() */
	__u64 bpf_cookie;
};
#define bpf_tracepoint_opts__last_field bpf_cookie

LIBBPF_API struct bpf_link *
bpf_program__attach_tracepoint(const struct bpf_program *prog,
			       const char *tp_category,
			       const char *tp_name);
LIBBPF_API struct bpf_link *
bpf_program__attach_tracepoint_opts(const struct bpf_program *prog,
				    const char *tp_category,
				    const char *tp_name,
				    const struct bpf_tracepoint_opts *opts);

LIBBPF_API struct bpf_link *
bpf_program__attach_raw_tracepoint(const struct bpf_program *prog,
				   const char *tp_name);
LIBBPF_API struct bpf_link *
bpf_program__attach_trace(const struct bpf_program *prog);
LIBBPF_API struct bpf_link *
bpf_program__attach_lsm(const struct bpf_program *prog);
LIBBPF_API struct bpf_link *
bpf_program__attach_cgroup(const struct bpf_program *prog, int cgroup_fd);
LIBBPF_API struct bpf_link *
bpf_program__attach_netns(const struct bpf_program *prog, int netns_fd);
LIBBPF_API struct bpf_link *
bpf_program__attach_xdp(const struct bpf_program *prog, int ifindex);
LIBBPF_API struct bpf_link *
bpf_program__attach_freplace(const struct bpf_program *prog,
			     int target_fd, const char *attach_func_name);

struct bpf_map;

LIBBPF_API struct bpf_link *bpf_map__attach_struct_ops(const struct bpf_map *map);

struct bpf_iter_attach_opts {
	size_t sz; /* size of this struct for forward/backward compatibility */
	union bpf_iter_link_info *link_info;
	__u32 link_info_len;
};
#define bpf_iter_attach_opts__last_field link_info_len

LIBBPF_API struct bpf_link *
bpf_program__attach_iter(const struct bpf_program *prog,
			 const struct bpf_iter_attach_opts *opts);

/*
 * Libbpf allows callers to adjust BPF programs before being loaded
 * into kernel. One program in an object file can be transformed into
 * multiple variants to be attached to different hooks.
 *
 * bpf_program_prep_t, bpf_program__set_prep and bpf_program__nth_fd
 * form an API for this purpose.
 *
 * - bpf_program_prep_t:
 *   Defines a 'preprocessor', which is a caller defined function
 *   passed to libbpf through bpf_program__set_prep(), and will be
 *   called before program is loaded. The processor should adjust
 *   the program one time for each instance according to the instance id
 *   passed to it.
 *
 * - bpf_program__set_prep:
 *   Attaches a preprocessor to a BPF program. The number of instances
 *   that should be created is also passed through this function.
 *
 * - bpf_program__nth_fd:
 *   After the program is loaded, get resulting FD of a given instance
 *   of the BPF program.
 *
 * If bpf_program__set_prep() is not used, the program would be loaded
 * without adjustment during bpf_object__load(). The program has only
 * one instance. In this case bpf_program__fd(prog) is equal to
 * bpf_program__nth_fd(prog, 0).
 */
struct bpf_prog_prep_result {
	/*
	 * If not NULL, load new instruction array.
	 * If set to NULL, don't load this instance.
	 */
	struct bpf_insn *new_insn_ptr;
	int new_insn_cnt;

	/* If not NULL, result FD is written to it. */
	int *pfd;
};

/*
 * Parameters of bpf_program_prep_t:
 *  - prog:	The bpf_program being loaded.
 *  - n:	Index of instance being generated.
 *  - insns:	BPF instructions array.
 *  - insns_cnt:Number of instructions in insns.
 *  - res:	Output parameter, result of transformation.
 *
 * Return value:
 *  - Zero:	pre-processing success.
 *  - Non-zero:	pre-processing error, stop loading.
 */
typedef int (*bpf_program_prep_t)(struct bpf_program *prog, int n,
				  struct bpf_insn *insns, int insns_cnt,
				  struct bpf_prog_prep_result *res);

LIBBPF_DEPRECATED_SINCE(0, 7, "use bpf_program__insns() for getting bpf_program instructions")
LIBBPF_API int bpf_program__set_prep(struct bpf_program *prog, int nr_instance,
				     bpf_program_prep_t prep);

LIBBPF_DEPRECATED_SINCE(0, 7, "multi-instance bpf_program support is deprecated")
LIBBPF_API int bpf_program__nth_fd(const struct bpf_program *prog, int n);

/*
 * Adjust type of BPF program. Default is kprobe.
 */
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_socket_filter(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_tracepoint(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_raw_tracepoint(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_kprobe(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_lsm(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_sched_cls(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_sched_act(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_xdp(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_perf_event(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_tracing(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_struct_ops(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_extension(struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__set_type() instead")
LIBBPF_API int bpf_program__set_sk_lookup(struct bpf_program *prog);

LIBBPF_API enum bpf_prog_type bpf_program__type(const struct bpf_program *prog);
LIBBPF_API void bpf_program__set_type(struct bpf_program *prog,
				      enum bpf_prog_type type);

LIBBPF_API enum bpf_attach_type
bpf_program__expected_attach_type(const struct bpf_program *prog);
LIBBPF_API void
bpf_program__set_expected_attach_type(struct bpf_program *prog,
				      enum bpf_attach_type type);

LIBBPF_API __u32 bpf_program__flags(const struct bpf_program *prog);
LIBBPF_API int bpf_program__set_flags(struct bpf_program *prog, __u32 flags);

/* Per-program log level and log buffer getters/setters.
 * See bpf_object_open_opts comments regarding log_level and log_buf
 * interactions.
 */
LIBBPF_API __u32 bpf_program__log_level(const struct bpf_program *prog);
LIBBPF_API int bpf_program__set_log_level(struct bpf_program *prog, __u32 log_level);
LIBBPF_API const char *bpf_program__log_buf(const struct bpf_program *prog, size_t *log_size);
LIBBPF_API int bpf_program__set_log_buf(struct bpf_program *prog, char *log_buf, size_t log_size);

LIBBPF_API int
bpf_program__set_attach_target(struct bpf_program *prog, int attach_prog_fd,
			       const char *attach_func_name);

LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_socket_filter(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_tracepoint(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_raw_tracepoint(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_kprobe(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_lsm(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_sched_cls(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_sched_act(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_xdp(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_perf_event(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_tracing(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_struct_ops(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_extension(const struct bpf_program *prog);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_program__type() instead")
LIBBPF_API bool bpf_program__is_sk_lookup(const struct bpf_program *prog);

/*
 * No need for __attribute__((packed)), all members of 'bpf_map_def'
 * are all aligned.  In addition, using __attribute__((packed))
 * would trigger a -Wpacked warning message, and lead to an error
 * if -Werror is set.
 */
struct bpf_map_def {
	unsigned int type;
	unsigned int key_size;
	unsigned int value_size;
	unsigned int max_entries;
	unsigned int map_flags;
};

/**
 * @brief **bpf_object__find_map_by_name()** returns BPF map of
 * the given name, if it exists within the passed BPF object
 * @param obj BPF object
 * @param name name of the BPF map
 * @return BPF map instance, if such map exists within the BPF object;
 * or NULL otherwise.
 */
LIBBPF_API struct bpf_map *
bpf_object__find_map_by_name(const struct bpf_object *obj, const char *name);

LIBBPF_API int
bpf_object__find_map_fd_by_name(const struct bpf_object *obj, const char *name);

/*
 * Get bpf_map through the offset of corresponding struct bpf_map_def
 * in the BPF object file.
 */
LIBBPF_API LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_object__find_map_by_name() instead")
struct bpf_map *
bpf_object__find_map_by_offset(struct bpf_object *obj, size_t offset);

LIBBPF_API LIBBPF_DEPRECATED_SINCE(0, 7, "use bpf_object__next_map() instead")
struct bpf_map *bpf_map__next(const struct bpf_map *map, const struct bpf_object *obj);
LIBBPF_API struct bpf_map *
bpf_object__next_map(const struct bpf_object *obj, const struct bpf_map *map);

#define bpf_object__for_each_map(pos, obj)		\
	for ((pos) = bpf_object__next_map((obj), NULL);	\
	     (pos) != NULL;				\
	     (pos) = bpf_object__next_map((obj), (pos)))
#define bpf_map__for_each bpf_object__for_each_map

LIBBPF_API LIBBPF_DEPRECATED_SINCE(0, 7, "use bpf_object__prev_map() instead")
struct bpf_map *bpf_map__prev(const struct bpf_map *map, const struct bpf_object *obj);
LIBBPF_API struct bpf_map *
bpf_object__prev_map(const struct bpf_object *obj, const struct bpf_map *map);

/**
 * @brief **bpf_map__fd()** gets the file descriptor of the passed
 * BPF map
 * @param map the BPF map instance
 * @return the file descriptor; or -EINVAL in case of an error
 */
LIBBPF_API int bpf_map__fd(const struct bpf_map *map);
LIBBPF_API int bpf_map__reuse_fd(struct bpf_map *map, int fd);
/* get map definition */
LIBBPF_API LIBBPF_DEPRECATED_SINCE(0, 8, "use appropriate getters or setters instead")
const struct bpf_map_def *bpf_map__def(const struct bpf_map *map);
/* get map name */
LIBBPF_API const char *bpf_map__name(const struct bpf_map *map);
/* get/set map type */
LIBBPF_API enum bpf_map_type bpf_map__type(const struct bpf_map *map);
LIBBPF_API int bpf_map__set_type(struct bpf_map *map, enum bpf_map_type type);
/* get/set map size (max_entries) */
LIBBPF_API __u32 bpf_map__max_entries(const struct bpf_map *map);
LIBBPF_API int bpf_map__set_max_entries(struct bpf_map *map, __u32 max_entries);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_map__set_max_entries() instead")
LIBBPF_API int bpf_map__resize(struct bpf_map *map, __u32 max_entries);
/* get/set map flags */
LIBBPF_API __u32 bpf_map__map_flags(const struct bpf_map *map);
LIBBPF_API int bpf_map__set_map_flags(struct bpf_map *map, __u32 flags);
/* get/set map NUMA node */
LIBBPF_API __u32 bpf_map__numa_node(const struct bpf_map *map);
LIBBPF_API int bpf_map__set_numa_node(struct bpf_map *map, __u32 numa_node);
/* get/set map key size */
LIBBPF_API __u32 bpf_map__key_size(const struct bpf_map *map);
LIBBPF_API int bpf_map__set_key_size(struct bpf_map *map, __u32 size);
/* get/set map value size */
LIBBPF_API __u32 bpf_map__value_size(const struct bpf_map *map);
LIBBPF_API int bpf_map__set_value_size(struct bpf_map *map, __u32 size);
/* get map key/value BTF type IDs */
LIBBPF_API __u32 bpf_map__btf_key_type_id(const struct bpf_map *map);
LIBBPF_API __u32 bpf_map__btf_value_type_id(const struct bpf_map *map);
/* get/set map if_index */
LIBBPF_API __u32 bpf_map__ifindex(const struct bpf_map *map);
LIBBPF_API int bpf_map__set_ifindex(struct bpf_map *map, __u32 ifindex);
/* get/set map map_extra flags */
LIBBPF_API __u64 bpf_map__map_extra(const struct bpf_map *map);
LIBBPF_API int bpf_map__set_map_extra(struct bpf_map *map, __u64 map_extra);

typedef void (*bpf_map_clear_priv_t)(struct bpf_map *, void *);
LIBBPF_DEPRECATED_SINCE(0, 7, "storage via set_priv/priv is deprecated")
LIBBPF_API int bpf_map__set_priv(struct bpf_map *map, void *priv,
				 bpf_map_clear_priv_t clear_priv);
LIBBPF_DEPRECATED_SINCE(0, 7, "storage via set_priv/priv is deprecated")
LIBBPF_API void *bpf_map__priv(const struct bpf_map *map);
LIBBPF_API int bpf_map__set_initial_value(struct bpf_map *map,
					  const void *data, size_t size);
LIBBPF_API const void *bpf_map__initial_value(struct bpf_map *map, size_t *psize);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_map__type() instead")
LIBBPF_API bool bpf_map__is_offload_neutral(const struct bpf_map *map);

/**
 * @brief **bpf_map__is_internal()** tells the caller whether or not the
 * passed map is a special map created by libbpf automatically for things like
 * global variables, __ksym externs, Kconfig values, etc
 * @param map the bpf_map
 * @return true, if the map is an internal map; false, otherwise
 */
LIBBPF_API bool bpf_map__is_internal(const struct bpf_map *map);
LIBBPF_API int bpf_map__set_pin_path(struct bpf_map *map, const char *path);
LIBBPF_API const char *bpf_map__pin_path(const struct bpf_map *map);
LIBBPF_API bool bpf_map__is_pinned(const struct bpf_map *map);
LIBBPF_API int bpf_map__pin(struct bpf_map *map, const char *path);
LIBBPF_API int bpf_map__unpin(struct bpf_map *map, const char *path);

LIBBPF_API int bpf_map__set_inner_map_fd(struct bpf_map *map, int fd);
LIBBPF_API struct bpf_map *bpf_map__inner_map(struct bpf_map *map);

/**
 * @brief **libbpf_get_error()** extracts the error code from the passed
 * pointer
 * @param ptr pointer returned from libbpf API function
 * @return error code; or 0 if no error occured
 *
 * Many libbpf API functions which return pointers have logic to encode error
 * codes as pointers, and do not return NULL. Meaning **libbpf_get_error()**
 * should be used on the return value from these functions immediately after
 * calling the API function, with no intervening calls that could clobber the
 * `errno` variable. Consult the individual functions documentation to verify
 * if this logic applies should be used.
 *
 * For these API functions, if `libbpf_set_strict_mode(LIBBPF_STRICT_CLEAN_PTRS)`
 * is enabled, NULL is returned on error instead.
 *
 * If ptr is NULL, then errno should be already set by the failing
 * API, because libbpf never returns NULL on success and it now always
 * sets errno on error.
 *
 * Example usage:
 *
 *   struct perf_buffer *pb;
 *
 *   pb = perf_buffer__new(bpf_map__fd(obj->maps.events), PERF_BUFFER_PAGES, &opts);
 *   err = libbpf_get_error(pb);
 *   if (err) {
 *	  pb = NULL;
 *	  fprintf(stderr, "failed to open perf buffer: %d\n", err);
 *	  goto cleanup;
 *   }
 */
LIBBPF_API long libbpf_get_error(const void *ptr);

struct bpf_prog_load_attr {
	const char *file;
	enum bpf_prog_type prog_type;
	enum bpf_attach_type expected_attach_type;
	int ifindex;
	int log_level;
	int prog_flags;
};

LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_object__open() and bpf_object__load() instead")
LIBBPF_API int bpf_prog_load_xattr(const struct bpf_prog_load_attr *attr,
				   struct bpf_object **pobj, int *prog_fd);
LIBBPF_DEPRECATED_SINCE(0, 7, "use bpf_object__open() and bpf_object__load() instead")
LIBBPF_API int bpf_prog_load_deprecated(const char *file, enum bpf_prog_type type,
					struct bpf_object **pobj, int *prog_fd);

/* XDP related API */
struct xdp_link_info {
	__u32 prog_id;
	__u32 drv_prog_id;
	__u32 hw_prog_id;
	__u32 skb_prog_id;
	__u8 attach_mode;
};

struct bpf_xdp_set_link_opts {
	size_t sz;
	int old_fd;
	size_t :0;
};
#define bpf_xdp_set_link_opts__last_field old_fd

LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_xdp_attach() instead")
LIBBPF_API int bpf_set_link_xdp_fd(int ifindex, int fd, __u32 flags);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_xdp_attach() instead")
LIBBPF_API int bpf_set_link_xdp_fd_opts(int ifindex, int fd, __u32 flags,
					const struct bpf_xdp_set_link_opts *opts);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_xdp_query_id() instead")
LIBBPF_API int bpf_get_link_xdp_id(int ifindex, __u32 *prog_id, __u32 flags);
LIBBPF_DEPRECATED_SINCE(0, 8, "use bpf_xdp_query() instead")
LIBBPF_API int bpf_get_link_xdp_info(int ifindex, struct xdp_link_info *info,
				     size_t info_size, __u32 flags);

struct bpf_xdp_attach_opts {
	size_t sz;
	int old_prog_fd;
	size_t :0;
};
#define bpf_xdp_attach_opts__last_field old_prog_fd

struct bpf_xdp_query_opts {
	size_t sz;
	__u32 prog_id;		/* output */
	__u32 drv_prog_id;	/* output */
	__u32 hw_prog_id;	/* output */
	__u32 skb_prog_id;	/* output */
	__u8 attach_mode;	/* output */
	size_t :0;
};
#define bpf_xdp_query_opts__last_field attach_mode

LIBBPF_API int bpf_xdp_attach(int ifindex, int prog_fd, __u32 flags,
			      const struct bpf_xdp_attach_opts *opts);
LIBBPF_API int bpf_xdp_detach(int ifindex, __u32 flags,
			      const struct bpf_xdp_attach_opts *opts);
LIBBPF_API int bpf_xdp_query(int ifindex, int flags, struct bpf_xdp_query_opts *opts);
LIBBPF_API int bpf_xdp_query_id(int ifindex, int flags, __u32 *prog_id);

/* TC related API */
enum bpf_tc_attach_point {
	BPF_TC_INGRESS = 1 << 0,
	BPF_TC_EGRESS  = 1 << 1,
	BPF_TC_CUSTOM  = 1 << 2,
};

#define BPF_TC_PARENT(a, b) 	\
	((((a) << 16) & 0xFFFF0000U) | ((b) & 0x0000FFFFU))

enum bpf_tc_flags {
	BPF_TC_F_REPLACE = 1 << 0,
};

struct bpf_tc_hook {
	size_t sz;
	int ifindex;
	enum bpf_tc_attach_point attach_point;
	__u32 parent;
	size_t :0;
};
#define bpf_tc_hook__last_field parent

struct bpf_tc_opts {
	size_t sz;
	int prog_fd;
	__u32 flags;
	__u32 prog_id;
	__u32 handle;
	__u32 priority;
	size_t :0;
};
#define bpf_tc_opts__last_field priority

LIBBPF_API int bpf_tc_hook_create(struct bpf_tc_hook *hook);
LIBBPF_API int bpf_tc_hook_destroy(struct bpf_tc_hook *hook);
LIBBPF_API int bpf_tc_attach(const struct bpf_tc_hook *hook,
			     struct bpf_tc_opts *opts);
LIBBPF_API int bpf_tc_detach(const struct bpf_tc_hook *hook,
			     const struct bpf_tc_opts *opts);
LIBBPF_API int bpf_tc_query(const struct bpf_tc_hook *hook,
			    struct bpf_tc_opts *opts);

/* Ring buffer APIs */
struct ring_buffer;

typedef int (*ring_buffer_sample_fn)(void *ctx, void *data, size_t size);

struct ring_buffer_opts {
	size_t sz; /* size of this struct, for forward/backward compatiblity */
};

#define ring_buffer_opts__last_field sz

LIBBPF_API struct ring_buffer *
ring_buffer__new(int map_fd, ring_buffer_sample_fn sample_cb, void *ctx,
		 const struct ring_buffer_opts *opts);
LIBBPF_API void ring_buffer__free(struct ring_buffer *rb);
LIBBPF_API int ring_buffer__add(struct ring_buffer *rb, int map_fd,
				ring_buffer_sample_fn sample_cb, void *ctx);
LIBBPF_API int ring_buffer__poll(struct ring_buffer *rb, int timeout_ms);
LIBBPF_API int ring_buffer__consume(struct ring_buffer *rb);
LIBBPF_API int ring_buffer__epoll_fd(const struct ring_buffer *rb);

/* Perf buffer APIs */
struct perf_buffer;

typedef void (*perf_buffer_sample_fn)(void *ctx, int cpu,
				      void *data, __u32 size);
typedef void (*perf_buffer_lost_fn)(void *ctx, int cpu, __u64 cnt);

/* common use perf buffer options */
struct perf_buffer_opts {
	union {
		size_t sz;
		struct { /* DEPRECATED: will be removed in v1.0 */
			/* if specified, sample_cb is called for each sample */
			perf_buffer_sample_fn sample_cb;
			/* if specified, lost_cb is called for each batch of lost samples */
			perf_buffer_lost_fn lost_cb;
			/* ctx is provided to sample_cb and lost_cb */
			void *ctx;
		};
	};
};
#define perf_buffer_opts__last_field sz

/**
 * @brief **perf_buffer__new()** creates BPF perfbuf manager for a specified
 * BPF_PERF_EVENT_ARRAY map
 * @param map_fd FD of BPF_PERF_EVENT_ARRAY BPF map that will be used by BPF
 * code to send data over to user-space
 * @param page_cnt number of memory pages allocated for each per-CPU buffer
 * @param sample_cb function called on each received data record
 * @param lost_cb function called when record loss has occurred
 * @param ctx user-provided extra context passed into *sample_cb* and *lost_cb*
 * @return a new instance of struct perf_buffer on success, NULL on error with
 * *errno* containing an error code
 */
LIBBPF_API struct perf_buffer *
perf_buffer__new(int map_fd, size_t page_cnt,
		 perf_buffer_sample_fn sample_cb, perf_buffer_lost_fn lost_cb, void *ctx,
		 const struct perf_buffer_opts *opts);

LIBBPF_API struct perf_buffer *
perf_buffer__new_v0_6_0(int map_fd, size_t page_cnt,
			perf_buffer_sample_fn sample_cb, perf_buffer_lost_fn lost_cb, void *ctx,
			const struct perf_buffer_opts *opts);

LIBBPF_API LIBBPF_DEPRECATED_SINCE(0, 7, "use new variant of perf_buffer__new() instead")
struct perf_buffer *perf_buffer__new_deprecated(int map_fd, size_t page_cnt,
						const struct perf_buffer_opts *opts);

#define perf_buffer__new(...) ___libbpf_overload(___perf_buffer_new, __VA_ARGS__)
#define ___perf_buffer_new6(map_fd, page_cnt, sample_cb, lost_cb, ctx, opts) \
	perf_buffer__new(map_fd, page_cnt, sample_cb, lost_cb, ctx, opts)
#define ___perf_buffer_new3(map_fd, page_cnt, opts) \
	perf_buffer__new_deprecated(map_fd, page_cnt, opts)

enum bpf_perf_event_ret {
	LIBBPF_PERF_EVENT_DONE	= 0,
	LIBBPF_PERF_EVENT_ERROR	= -1,
	LIBBPF_PERF_EVENT_CONT	= -2,
};

struct perf_event_header;

typedef enum bpf_perf_event_ret
(*perf_buffer_event_fn)(void *ctx, int cpu, struct perf_event_header *event);

/* raw perf buffer options, giving most power and control */
struct perf_buffer_raw_opts {
	union {
		struct {
			size_t sz;
			long :0;
			long :0;
		};
		struct { /* DEPRECATED: will be removed in v1.0 */
			/* perf event attrs passed directly into perf_event_open() */
			struct perf_event_attr *attr;
			/* raw event callback */
			perf_buffer_event_fn event_cb;
			/* ctx is provided to event_cb */
			void *ctx;
		};
	};
	/* if cpu_cnt == 0, open all on all possible CPUs (up to the number of
	 * max_entries of given PERF_EVENT_ARRAY map)
	 */
	int cpu_cnt;
	/* if cpu_cnt > 0, cpus is an array of CPUs to open ring buffers on */
	int *cpus;
	/* if cpu_cnt > 0, map_keys specify map keys to set per-CPU FDs for */
	int *map_keys;
};
#define perf_buffer_raw_opts__last_field map_keys

LIBBPF_API struct perf_buffer *
perf_buffer__new_raw(int map_fd, size_t page_cnt, struct perf_event_attr *attr,
		     perf_buffer_event_fn event_cb, void *ctx,
		     const struct perf_buffer_raw_opts *opts);

LIBBPF_API struct perf_buffer *
perf_buffer__new_raw_v0_6_0(int map_fd, size_t page_cnt, struct perf_event_attr *attr,
			    perf_buffer_event_fn event_cb, void *ctx,
			    const struct perf_buffer_raw_opts *opts);

LIBBPF_API LIBBPF_DEPRECATED_SINCE(0, 7, "use new variant of perf_buffer__new_raw() instead")
struct perf_buffer *perf_buffer__new_raw_deprecated(int map_fd, size_t page_cnt,
						    const struct perf_buffer_raw_opts *opts);

#define perf_buffer__new_raw(...) ___libbpf_overload(___perf_buffer_new_raw, __VA_ARGS__)
#define ___perf_buffer_new_raw6(map_fd, page_cnt, attr, event_cb, ctx, opts) \
	perf_buffer__new_raw(map_fd, page_cnt, attr, event_cb, ctx, opts)
#define ___perf_buffer_new_raw3(map_fd, page_cnt, opts) \
	perf_buffer__new_raw_deprecated(map_fd, page_cnt, opts)

LIBBPF_API void perf_buffer__free(struct perf_buffer *pb);
LIBBPF_API int perf_buffer__epoll_fd(const struct perf_buffer *pb);
LIBBPF_API int perf_buffer__poll(struct perf_buffer *pb, int timeout_ms);
LIBBPF_API int perf_buffer__consume(struct perf_buffer *pb);
LIBBPF_API int perf_buffer__consume_buffer(struct perf_buffer *pb, size_t buf_idx);
LIBBPF_API size_t perf_buffer__buffer_cnt(const struct perf_buffer *pb);
LIBBPF_API int perf_buffer__buffer_fd(const struct perf_buffer *pb, size_t buf_idx);

typedef enum bpf_perf_event_ret
	(*bpf_perf_event_print_t)(struct perf_event_header *hdr,
				  void *private_data);
LIBBPF_DEPRECATED_SINCE(0, 8, "use perf_buffer__poll() or  perf_buffer__consume() instead")
LIBBPF_API enum bpf_perf_event_ret
bpf_perf_event_read_simple(void *mmap_mem, size_t mmap_size, size_t page_size,
			   void **copy_mem, size_t *copy_size,
			   bpf_perf_event_print_t fn, void *private_data);

struct bpf_prog_linfo;
struct bpf_prog_info;

LIBBPF_API void bpf_prog_linfo__free(struct bpf_prog_linfo *prog_linfo);
LIBBPF_API struct bpf_prog_linfo *
bpf_prog_linfo__new(const struct bpf_prog_info *info);
LIBBPF_API const struct bpf_line_info *
bpf_prog_linfo__lfind_addr_func(const struct bpf_prog_linfo *prog_linfo,
				__u64 addr, __u32 func_idx, __u32 nr_skip);
LIBBPF_API const struct bpf_line_info *
bpf_prog_linfo__lfind(const struct bpf_prog_linfo *prog_linfo,
		      __u32 insn_off, __u32 nr_skip);

/*
 * Probe for supported system features
 *
 * Note that running many of these probes in a short amount of time can cause
 * the kernel to reach the maximal size of lockable memory allowed for the
 * user, causing subsequent probes to fail. In this case, the caller may want
 * to adjust that limit with setrlimit().
 */
LIBBPF_DEPRECATED_SINCE(0, 8, "use libbpf_probe_bpf_prog_type() instead")
LIBBPF_API bool bpf_probe_prog_type(enum bpf_prog_type prog_type, __u32 ifindex);
LIBBPF_DEPRECATED_SINCE(0, 8, "use libbpf_probe_bpf_map_type() instead")
LIBBPF_API bool bpf_probe_map_type(enum bpf_map_type map_type, __u32 ifindex);
LIBBPF_DEPRECATED_SINCE(0, 8, "use libbpf_probe_bpf_helper() instead")
LIBBPF_API bool bpf_probe_helper(enum bpf_func_id id, enum bpf_prog_type prog_type, __u32 ifindex);
LIBBPF_DEPRECATED_SINCE(0, 8, "implement your own or use bpftool for feature detection")
LIBBPF_API bool bpf_probe_large_insn_limit(__u32 ifindex);

/**
 * @brief **libbpf_probe_bpf_prog_type()** detects if host kernel supports
 * BPF programs of a given type.
 * @param prog_type BPF program type to detect kernel support for
 * @param opts reserved for future extensibility, should be NULL
 * @return 1, if given program type is supported; 0, if given program type is
 * not supported; negative error code if feature detection failed or can't be
 * performed
 *
 * Make sure the process has required set of CAP_* permissions (or runs as
 * root) when performing feature checking.
 */
LIBBPF_API int libbpf_probe_bpf_prog_type(enum bpf_prog_type prog_type, const void *opts);
/**
 * @brief **libbpf_probe_bpf_map_type()** detects if host kernel supports
 * BPF maps of a given type.
 * @param map_type BPF map type to detect kernel support for
 * @param opts reserved for future extensibility, should be NULL
 * @return 1, if given map type is supported; 0, if given map type is
 * not supported; negative error code if feature detection failed or can't be
 * performed
 *
 * Make sure the process has required set of CAP_* permissions (or runs as
 * root) when performing feature checking.
 */
LIBBPF_API int libbpf_probe_bpf_map_type(enum bpf_map_type map_type, const void *opts);
/**
 * @brief **libbpf_probe_bpf_helper()** detects if host kernel supports the
 * use of a given BPF helper from specified BPF program type.
 * @param prog_type BPF program type used to check the support of BPF helper
 * @param helper_id BPF helper ID (enum bpf_func_id) to check support for
 * @param opts reserved for future extensibility, should be NULL
 * @return 1, if given combination of program type and helper is supported; 0,
 * if the combination is not supported; negative error code if feature
 * detection for provided input arguments failed or can't be performed
 *
 * Make sure the process has required set of CAP_* permissions (or runs as
 * root) when performing feature checking.
 */
LIBBPF_API int libbpf_probe_bpf_helper(enum bpf_prog_type prog_type,
				       enum bpf_func_id helper_id, const void *opts);

/*
 * Get bpf_prog_info in continuous memory
 *
 * struct bpf_prog_info has multiple arrays. The user has option to choose
 * arrays to fetch from kernel. The following APIs provide an uniform way to
 * fetch these data. All arrays in bpf_prog_info are stored in a single
 * continuous memory region. This makes it easy to store the info in a
 * file.
 *
 * Before writing bpf_prog_info_linear to files, it is necessary to
 * translate pointers in bpf_prog_info to offsets. Helper functions
 * bpf_program__bpil_addr_to_offs() and bpf_program__bpil_offs_to_addr()
 * are introduced to switch between pointers and offsets.
 *
 * Examples:
 *   # To fetch map_ids and prog_tags:
 *   __u64 arrays = (1UL << BPF_PROG_INFO_MAP_IDS) |
 *           (1UL << BPF_PROG_INFO_PROG_TAGS);
 *   struct bpf_prog_info_linear *info_linear =
 *           bpf_program__get_prog_info_linear(fd, arrays);
 *
 *   # To save data in file
 *   bpf_program__bpil_addr_to_offs(info_linear);
 *   write(f, info_linear, sizeof(*info_linear) + info_linear->data_len);
 *
 *   # To read data from file
 *   read(f, info_linear, <proper_size>);
 *   bpf_program__bpil_offs_to_addr(info_linear);
 */
enum bpf_prog_info_array {
	BPF_PROG_INFO_FIRST_ARRAY = 0,
	BPF_PROG_INFO_JITED_INSNS = 0,
	BPF_PROG_INFO_XLATED_INSNS,
	BPF_PROG_INFO_MAP_IDS,
	BPF_PROG_INFO_JITED_KSYMS,
	BPF_PROG_INFO_JITED_FUNC_LENS,
	BPF_PROG_INFO_FUNC_INFO,
	BPF_PROG_INFO_LINE_INFO,
	BPF_PROG_INFO_JITED_LINE_INFO,
	BPF_PROG_INFO_PROG_TAGS,
	BPF_PROG_INFO_LAST_ARRAY,
};

struct bpf_prog_info_linear {
	/* size of struct bpf_prog_info, when the tool is compiled */
	__u32			info_len;
	/* total bytes allocated for data, round up to 8 bytes */
	__u32			data_len;
	/* which arrays are included in data */
	__u64			arrays;
	struct bpf_prog_info	info;
	__u8			data[];
};

LIBBPF_DEPRECATED_SINCE(0, 6, "use a custom linear prog_info wrapper")
LIBBPF_API struct bpf_prog_info_linear *
bpf_program__get_prog_info_linear(int fd, __u64 arrays);

LIBBPF_DEPRECATED_SINCE(0, 6, "use a custom linear prog_info wrapper")
LIBBPF_API void
bpf_program__bpil_addr_to_offs(struct bpf_prog_info_linear *info_linear);

LIBBPF_DEPRECATED_SINCE(0, 6, "use a custom linear prog_info wrapper")
LIBBPF_API void
bpf_program__bpil_offs_to_addr(struct bpf_prog_info_linear *info_linear);

/**
 * @brief **libbpf_num_possible_cpus()** is a helper function to get the
 * number of possible CPUs that the host kernel supports and expects.
 * @return number of possible CPUs; or error code on failure
 *
 * Example usage:
 *
 *     int ncpus = libbpf_num_possible_cpus();
 *     if (ncpus < 0) {
 *          // error handling
 *     }
 *     long values[ncpus];
 *     bpf_map_lookup_elem(per_cpu_map_fd, key, values);
 */
LIBBPF_API int libbpf_num_possible_cpus(void);

struct bpf_map_skeleton {
	const char *name;
	struct bpf_map **map;
	void **mmaped;
};

struct bpf_prog_skeleton {
	const char *name;
	struct bpf_program **prog;
	struct bpf_link **link;
};

struct bpf_object_skeleton {
	size_t sz; /* size of this struct, for forward/backward compatibility */

	const char *name;
	const void *data;
	size_t data_sz;

	struct bpf_object **obj;

	int map_cnt;
	int map_skel_sz; /* sizeof(struct bpf_map_skeleton) */
	struct bpf_map_skeleton *maps;

	int prog_cnt;
	int prog_skel_sz; /* sizeof(struct bpf_prog_skeleton) */
	struct bpf_prog_skeleton *progs;
};

LIBBPF_API int
bpf_object__open_skeleton(struct bpf_object_skeleton *s,
			  const struct bpf_object_open_opts *opts);
LIBBPF_API int bpf_object__load_skeleton(struct bpf_object_skeleton *s);
LIBBPF_API int bpf_object__attach_skeleton(struct bpf_object_skeleton *s);
LIBBPF_API void bpf_object__detach_skeleton(struct bpf_object_skeleton *s);
LIBBPF_API void bpf_object__destroy_skeleton(struct bpf_object_skeleton *s);

struct gen_loader_opts {
	size_t sz; /* size of this struct, for forward/backward compatiblity */
	const char *data;
	const char *insns;
	__u32 data_sz;
	__u32 insns_sz;
};

#define gen_loader_opts__last_field insns_sz
LIBBPF_API int bpf_object__gen_loader(struct bpf_object *obj,
				      struct gen_loader_opts *opts);

enum libbpf_tristate {
	TRI_NO = 0,
	TRI_YES = 1,
	TRI_MODULE = 2,
};

struct bpf_linker_opts {
	/* size of this struct, for forward/backward compatiblity */
	size_t sz;
};
#define bpf_linker_opts__last_field sz

struct bpf_linker_file_opts {
	/* size of this struct, for forward/backward compatiblity */
	size_t sz;
};
#define bpf_linker_file_opts__last_field sz

struct bpf_linker;

LIBBPF_API struct bpf_linker *bpf_linker__new(const char *filename, struct bpf_linker_opts *opts);
LIBBPF_API int bpf_linker__add_file(struct bpf_linker *linker,
				    const char *filename,
				    const struct bpf_linker_file_opts *opts);
LIBBPF_API int bpf_linker__finalize(struct bpf_linker *linker);
LIBBPF_API void bpf_linker__free(struct bpf_linker *linker);

/*
 * Custom handling of BPF program's SEC() definitions
 */

struct bpf_prog_load_opts; /* defined in bpf.h */

/* Called during bpf_object__open() for each recognized BPF program. Callback
 * can use various bpf_program__set_*() setters to adjust whatever properties
 * are necessary.
 */
typedef int (*libbpf_prog_setup_fn_t)(struct bpf_program *prog, long cookie);

/* Called right before libbpf performs bpf_prog_load() to load BPF program
 * into the kernel. Callback can adjust opts as necessary.
 */
typedef int (*libbpf_prog_prepare_load_fn_t)(struct bpf_program *prog,
					     struct bpf_prog_load_opts *opts, long cookie);

/* Called during skeleton attach or through bpf_program__attach(). If
 * auto-attach is not supported, callback should return 0 and set link to
 * NULL (it's not considered an error during skeleton attach, but it will be
 * an error for bpf_program__attach() calls). On error, error should be
 * returned directly and link set to NULL. On success, return 0 and set link
 * to a valid struct bpf_link.
 */
typedef int (*libbpf_prog_attach_fn_t)(const struct bpf_program *prog, long cookie,
				       struct bpf_link **link);

struct libbpf_prog_handler_opts {
	/* size of this struct, for forward/backward compatiblity */
	size_t sz;
	/* User-provided value that is passed to prog_setup_fn,
	 * prog_prepare_load_fn, and prog_attach_fn callbacks. Allows user to
	 * register one set of callbacks for multiple SEC() definitions and
	 * still be able to distinguish them, if necessary. For example,
	 * libbpf itself is using this to pass necessary flags (e.g.,
	 * sleepable flag) to a common internal SEC() handler.
	 */
	long cookie;
	/* BPF program initialization callback (see libbpf_prog_setup_fn_t).
	 * Callback is optional, pass NULL if it's not necessary.
	 */
	libbpf_prog_setup_fn_t prog_setup_fn;
	/* BPF program loading callback (see libbpf_prog_prepare_load_fn_t).
	 * Callback is optional, pass NULL if it's not necessary.
	 */
	libbpf_prog_prepare_load_fn_t prog_prepare_load_fn;
	/* BPF program attach callback (see libbpf_prog_attach_fn_t).
	 * Callback is optional, pass NULL if it's not necessary.
	 */
	libbpf_prog_attach_fn_t prog_attach_fn;
};
#define libbpf_prog_handler_opts__last_field prog_attach_fn

/**
 * @brief **libbpf_register_prog_handler()** registers a custom BPF program
 * SEC() handler.
 * @param sec section prefix for which custom handler is registered
 * @param prog_type BPF program type associated with specified section
 * @param exp_attach_type Expected BPF attach type associated with specified section
 * @param opts optional cookie, callbacks, and other extra options
 * @return Non-negative handler ID is returned on success. This handler ID has
 * to be passed to *libbpf_unregister_prog_handler()* to unregister such
 * custom handler. Negative error code is returned on error.
 *
 * *sec* defines which SEC() definitions are handled by this custom handler
 * registration. *sec* can have few different forms:
 *   - if *sec* is just a plain string (e.g., "abc"), it will match only
 *   SEC("abc"). If BPF program specifies SEC("abc/whatever") it will result
 *   in an error;
 *   - if *sec* is of the form "abc/", proper SEC() form is
 *   SEC("abc/something"), where acceptable "something" should be checked by
 *   *prog_init_fn* callback, if there are additional restrictions;
 *   - if *sec* is of the form "abc+", it will successfully match both
 *   SEC("abc") and SEC("abc/whatever") forms;
 *   - if *sec* is NULL, custom handler is registered for any BPF program that
 *   doesn't match any of the registered (custom or libbpf's own) SEC()
 *   handlers. There could be only one such generic custom handler registered
 *   at any given time.
 *
 * All custom handlers (except the one with *sec* == NULL) are processed
 * before libbpf's own SEC() handlers. It is allowed to "override" libbpf's
 * SEC() handlers by registering custom ones for the same section prefix
 * (i.e., it's possible to have custom SEC("perf_event/LLC-load-misses")
 * handler).
 *
 * Note, like much of global libbpf APIs (e.g., libbpf_set_print(),
 * libbpf_set_strict_mode(), etc)) these APIs are not thread-safe. User needs
 * to ensure synchronization if there is a risk of running this API from
 * multiple threads simultaneously.
 */
LIBBPF_API int libbpf_register_prog_handler(const char *sec,
					    enum bpf_prog_type prog_type,
					    enum bpf_attach_type exp_attach_type,
					    const struct libbpf_prog_handler_opts *opts);
/**
 * @brief *libbpf_unregister_prog_handler()* unregisters previously registered
 * custom BPF program SEC() handler.
 * @param handler_id handler ID returned by *libbpf_register_prog_handler()*
 * after successful registration
 * @return 0 on success, negative error code if handler isn't found
 *
 * Note, like much of global libbpf APIs (e.g., libbpf_set_print(),
 * libbpf_set_strict_mode(), etc)) these APIs are not thread-safe. User needs
 * to ensure synchronization if there is a risk of running this API from
 * multiple threads simultaneously.
 */
LIBBPF_API int libbpf_unregister_prog_handler(int handler_id);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* __LIBBPF_LIBBPF_H */
