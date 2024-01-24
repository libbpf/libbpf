// SPDX-License-Identifier: (LGPL-2.1 OR BSD-2-Clause)
/* Copyright (c) 2023 Meta Platforms, Inc. and affiliates. */
#include <linux/kernel.h>
#include <linux/filter.h>
#include "bpf.h"
#include "libbpf.h"
#include "libbpf_common.h"
#include "libbpf_internal.h"
#include "str_error.h"

static inline __u64 ptr_to_u64(const void *ptr)
{
	return (__u64)(unsigned long)ptr;
}

int probe_fd(int fd)
{
	if (fd >= 0)
		close(fd);
	return fd >= 0;
}

static int probe_kern_prog_name(void)
{
	const size_t attr_sz = offsetofend(union bpf_attr, prog_name);
	struct bpf_insn insns[] = {
		BPF_MOV64_IMM(BPF_REG_0, 0),
		BPF_EXIT_INSN(),
	};
	union bpf_attr attr;
	int ret;

	memset(&attr, 0, attr_sz);
	attr.prog_type = BPF_PROG_TYPE_SOCKET_FILTER;
	attr.license = ptr_to_u64("GPL");
	attr.insns = ptr_to_u64(insns);
	attr.insn_cnt = (__u32)ARRAY_SIZE(insns);
	libbpf_strlcpy(attr.prog_name, "libbpf_nametest", sizeof(attr.prog_name));

	/* make sure loading with name works */
	ret = sys_bpf_prog_load(&attr, attr_sz, PROG_LOAD_ATTEMPTS);
	return probe_fd(ret);
}

static int probe_kern_global_data(void)
{
	char *cp, errmsg[STRERR_BUFSIZE];
	struct bpf_insn insns[] = {
		BPF_LD_MAP_VALUE(BPF_REG_1, 0, 16),
		BPF_ST_MEM(BPF_DW, BPF_REG_1, 0, 42),
		BPF_MOV64_IMM(BPF_REG_0, 0),
		BPF_EXIT_INSN(),
	};
	int ret, map, insn_cnt = ARRAY_SIZE(insns);

	map = bpf_map_create(BPF_MAP_TYPE_ARRAY, "libbpf_global", sizeof(int), 32, 1, NULL);
	if (map < 0) {
		ret = -errno;
		cp = libbpf_strerror_r(ret, errmsg, sizeof(errmsg));
		pr_warn("Error in %s():%s(%d). Couldn't create simple array map.\n",
			__func__, cp, -ret);
		return ret;
	}

	insns[0].imm = map;

	ret = bpf_prog_load(BPF_PROG_TYPE_SOCKET_FILTER, NULL, "GPL", insns, insn_cnt, NULL);
	close(map);
	return probe_fd(ret);
}

static int probe_kern_btf(void)
{
	static const char strs[] = "\0int";
	__u32 types[] = {
		/* int */
		BTF_TYPE_INT_ENC(1, BTF_INT_SIGNED, 0, 32, 4),
	};

	return probe_fd(libbpf__load_raw_btf((char *)types, sizeof(types),
					     strs, sizeof(strs)));
}

static int probe_kern_btf_func(void)
{
	static const char strs[] = "\0int\0x\0a";
	/* void x(int a) {} */
	__u32 types[] = {
		/* int */
		BTF_TYPE_INT_ENC(1, BTF_INT_SIGNED, 0, 32, 4),  /* [1] */
		/* FUNC_PROTO */                                /* [2] */
		BTF_TYPE_ENC(0, BTF_INFO_ENC(BTF_KIND_FUNC_PROTO, 0, 1), 0),
		BTF_PARAM_ENC(7, 1),
		/* FUNC x */                                    /* [3] */
		BTF_TYPE_ENC(5, BTF_INFO_ENC(BTF_KIND_FUNC, 0, 0), 2),
	};

	return probe_fd(libbpf__load_raw_btf((char *)types, sizeof(types),
					     strs, sizeof(strs)));
}

static int probe_kern_btf_func_global(void)
{
	static const char strs[] = "\0int\0x\0a";
	/* static void x(int a) {} */
	__u32 types[] = {
		/* int */
		BTF_TYPE_INT_ENC(1, BTF_INT_SIGNED, 0, 32, 4),  /* [1] */
		/* FUNC_PROTO */                                /* [2] */
		BTF_TYPE_ENC(0, BTF_INFO_ENC(BTF_KIND_FUNC_PROTO, 0, 1), 0),
		BTF_PARAM_ENC(7, 1),
		/* FUNC x BTF_FUNC_GLOBAL */                    /* [3] */
		BTF_TYPE_ENC(5, BTF_INFO_ENC(BTF_KIND_FUNC, 0, BTF_FUNC_GLOBAL), 2),
	};

	return probe_fd(libbpf__load_raw_btf((char *)types, sizeof(types),
					     strs, sizeof(strs)));
}

static int probe_kern_btf_datasec(void)
{
	static const char strs[] = "\0x\0.data";
	/* static int a; */
	__u32 types[] = {
		/* int */
		BTF_TYPE_INT_ENC(0, BTF_INT_SIGNED, 0, 32, 4),  /* [1] */
		/* VAR x */                                     /* [2] */
		BTF_TYPE_ENC(1, BTF_INFO_ENC(BTF_KIND_VAR, 0, 0), 1),
		BTF_VAR_STATIC,
		/* DATASEC val */                               /* [3] */
		BTF_TYPE_ENC(3, BTF_INFO_ENC(BTF_KIND_DATASEC, 0, 1), 4),
		BTF_VAR_SECINFO_ENC(2, 0, 4),
	};

	return probe_fd(libbpf__load_raw_btf((char *)types, sizeof(types),
					     strs, sizeof(strs)));
}

static int probe_kern_btf_float(void)
{
	static const char strs[] = "\0float";
	__u32 types[] = {
		/* float */
		BTF_TYPE_FLOAT_ENC(1, 4),
	};

	return probe_fd(libbpf__load_raw_btf((char *)types, sizeof(types),
					     strs, sizeof(strs)));
}

static int probe_kern_btf_decl_tag(void)
{
	static const char strs[] = "\0tag";
	__u32 types[] = {
		/* int */
		BTF_TYPE_INT_ENC(0, BTF_INT_SIGNED, 0, 32, 4),  /* [1] */
		/* VAR x */                                     /* [2] */
		BTF_TYPE_ENC(1, BTF_INFO_ENC(BTF_KIND_VAR, 0, 0), 1),
		BTF_VAR_STATIC,
		/* attr */
		BTF_TYPE_DECL_TAG_ENC(1, 2, -1),
	};

	return probe_fd(libbpf__load_raw_btf((char *)types, sizeof(types),
					     strs, sizeof(strs)));
}

static int probe_kern_btf_type_tag(void)
{
	static const char strs[] = "\0tag";
	__u32 types[] = {
		/* int */
		BTF_TYPE_INT_ENC(0, BTF_INT_SIGNED, 0, 32, 4),		/* [1] */
		/* attr */
		BTF_TYPE_TYPE_TAG_ENC(1, 1),				/* [2] */
		/* ptr */
		BTF_TYPE_ENC(0, BTF_INFO_ENC(BTF_KIND_PTR, 0, 0), 2),	/* [3] */
	};

	return probe_fd(libbpf__load_raw_btf((char *)types, sizeof(types),
					     strs, sizeof(strs)));
}

static int probe_kern_array_mmap(void)
{
	LIBBPF_OPTS(bpf_map_create_opts, opts, .map_flags = BPF_F_MMAPABLE);
	int fd;

	fd = bpf_map_create(BPF_MAP_TYPE_ARRAY, "libbpf_mmap", sizeof(int), sizeof(int), 1, &opts);
	return probe_fd(fd);
}

static int probe_kern_exp_attach_type(void)
{
	LIBBPF_OPTS(bpf_prog_load_opts, opts, .expected_attach_type = BPF_CGROUP_INET_SOCK_CREATE);
	struct bpf_insn insns[] = {
		BPF_MOV64_IMM(BPF_REG_0, 0),
		BPF_EXIT_INSN(),
	};
	int fd, insn_cnt = ARRAY_SIZE(insns);

	/* use any valid combination of program type and (optional)
	 * non-zero expected attach type (i.e., not a BPF_CGROUP_INET_INGRESS)
	 * to see if kernel supports expected_attach_type field for
	 * BPF_PROG_LOAD command
	 */
	fd = bpf_prog_load(BPF_PROG_TYPE_CGROUP_SOCK, NULL, "GPL", insns, insn_cnt, &opts);
	return probe_fd(fd);
}

static int probe_kern_probe_read_kernel(void)
{
	struct bpf_insn insns[] = {
		BPF_MOV64_REG(BPF_REG_1, BPF_REG_10),	/* r1 = r10 (fp) */
		BPF_ALU64_IMM(BPF_ADD, BPF_REG_1, -8),	/* r1 += -8 */
		BPF_MOV64_IMM(BPF_REG_2, 8),		/* r2 = 8 */
		BPF_MOV64_IMM(BPF_REG_3, 0),		/* r3 = 0 */
		BPF_RAW_INSN(BPF_JMP | BPF_CALL, 0, 0, 0, BPF_FUNC_probe_read_kernel),
		BPF_EXIT_INSN(),
	};
	int fd, insn_cnt = ARRAY_SIZE(insns);

	fd = bpf_prog_load(BPF_PROG_TYPE_TRACEPOINT, NULL, "GPL", insns, insn_cnt, NULL);
	return probe_fd(fd);
}

static int probe_prog_bind_map(void)
{
	char *cp, errmsg[STRERR_BUFSIZE];
	struct bpf_insn insns[] = {
		BPF_MOV64_IMM(BPF_REG_0, 0),
		BPF_EXIT_INSN(),
	};
	int ret, map, prog, insn_cnt = ARRAY_SIZE(insns);

	map = bpf_map_create(BPF_MAP_TYPE_ARRAY, "libbpf_det_bind", sizeof(int), 32, 1, NULL);
	if (map < 0) {
		ret = -errno;
		cp = libbpf_strerror_r(ret, errmsg, sizeof(errmsg));
		pr_warn("Error in %s():%s(%d). Couldn't create simple array map.\n",
			__func__, cp, -ret);
		return ret;
	}

	prog = bpf_prog_load(BPF_PROG_TYPE_SOCKET_FILTER, NULL, "GPL", insns, insn_cnt, NULL);
	if (prog < 0) {
		close(map);
		return 0;
	}

	ret = bpf_prog_bind_map(prog, map, NULL);

	close(map);
	close(prog);

	return ret >= 0;
}

static int probe_module_btf(void)
{
	static const char strs[] = "\0int";
	__u32 types[] = {
		/* int */
		BTF_TYPE_INT_ENC(1, BTF_INT_SIGNED, 0, 32, 4),
	};
	struct bpf_btf_info info;
	__u32 len = sizeof(info);
	char name[16];
	int fd, err;

	fd = libbpf__load_raw_btf((char *)types, sizeof(types), strs, sizeof(strs));
	if (fd < 0)
		return 0; /* BTF not supported at all */

	memset(&info, 0, sizeof(info));
	info.name = ptr_to_u64(name);
	info.name_len = sizeof(name);

	/* check that BPF_OBJ_GET_INFO_BY_FD supports specifying name pointer;
	 * kernel's module BTF support coincides with support for
	 * name/name_len fields in struct bpf_btf_info.
	 */
	err = bpf_btf_get_info_by_fd(fd, &info, &len);
	close(fd);
	return !err;
}

static int probe_perf_link(void)
{
	struct bpf_insn insns[] = {
		BPF_MOV64_IMM(BPF_REG_0, 0),
		BPF_EXIT_INSN(),
	};
	int prog_fd, link_fd, err;

	prog_fd = bpf_prog_load(BPF_PROG_TYPE_TRACEPOINT, NULL, "GPL",
				insns, ARRAY_SIZE(insns), NULL);
	if (prog_fd < 0)
		return -errno;

	/* use invalid perf_event FD to get EBADF, if link is supported;
	 * otherwise EINVAL should be returned
	 */
	link_fd = bpf_link_create(prog_fd, -1, BPF_PERF_EVENT, NULL);
	err = -errno; /* close() can clobber errno */

	if (link_fd >= 0)
		close(link_fd);
	close(prog_fd);

	return link_fd < 0 && err == -EBADF;
}

static int probe_uprobe_multi_link(void)
{
	LIBBPF_OPTS(bpf_prog_load_opts, load_opts,
		.expected_attach_type = BPF_TRACE_UPROBE_MULTI,
	);
	LIBBPF_OPTS(bpf_link_create_opts, link_opts);
	struct bpf_insn insns[] = {
		BPF_MOV64_IMM(BPF_REG_0, 0),
		BPF_EXIT_INSN(),
	};
	int prog_fd, link_fd, err;
	unsigned long offset = 0;

	prog_fd = bpf_prog_load(BPF_PROG_TYPE_KPROBE, NULL, "GPL",
				insns, ARRAY_SIZE(insns), &load_opts);
	if (prog_fd < 0)
		return -errno;

	/* Creating uprobe in '/' binary should fail with -EBADF. */
	link_opts.uprobe_multi.path = "/";
	link_opts.uprobe_multi.offsets = &offset;
	link_opts.uprobe_multi.cnt = 1;

	link_fd = bpf_link_create(prog_fd, -1, BPF_TRACE_UPROBE_MULTI, &link_opts);
	err = -errno; /* close() can clobber errno */

	if (link_fd >= 0)
		close(link_fd);
	close(prog_fd);

	return link_fd < 0 && err == -EBADF;
}

static int probe_kern_bpf_cookie(void)
{
	struct bpf_insn insns[] = {
		BPF_RAW_INSN(BPF_JMP | BPF_CALL, 0, 0, 0, BPF_FUNC_get_attach_cookie),
		BPF_EXIT_INSN(),
	};
	int ret, insn_cnt = ARRAY_SIZE(insns);

	ret = bpf_prog_load(BPF_PROG_TYPE_KPROBE, NULL, "GPL", insns, insn_cnt, NULL);
	return probe_fd(ret);
}

static int probe_kern_btf_enum64(void)
{
	static const char strs[] = "\0enum64";
	__u32 types[] = {
		BTF_TYPE_ENC(1, BTF_INFO_ENC(BTF_KIND_ENUM64, 0, 0), 8),
	};

	return probe_fd(libbpf__load_raw_btf((char *)types, sizeof(types),
					     strs, sizeof(strs)));
}

typedef int (*feature_probe_fn)(void);

static struct kern_feature_cache feature_cache;

static struct kern_feature_desc {
	const char *desc;
	feature_probe_fn probe;
} feature_probes[__FEAT_CNT] = {
	[FEAT_PROG_NAME] = {
		"BPF program name", probe_kern_prog_name,
	},
	[FEAT_GLOBAL_DATA] = {
		"global variables", probe_kern_global_data,
	},
	[FEAT_BTF] = {
		"minimal BTF", probe_kern_btf,
	},
	[FEAT_BTF_FUNC] = {
		"BTF functions", probe_kern_btf_func,
	},
	[FEAT_BTF_GLOBAL_FUNC] = {
		"BTF global function", probe_kern_btf_func_global,
	},
	[FEAT_BTF_DATASEC] = {
		"BTF data section and variable", probe_kern_btf_datasec,
	},
	[FEAT_ARRAY_MMAP] = {
		"ARRAY map mmap()", probe_kern_array_mmap,
	},
	[FEAT_EXP_ATTACH_TYPE] = {
		"BPF_PROG_LOAD expected_attach_type attribute",
		probe_kern_exp_attach_type,
	},
	[FEAT_PROBE_READ_KERN] = {
		"bpf_probe_read_kernel() helper", probe_kern_probe_read_kernel,
	},
	[FEAT_PROG_BIND_MAP] = {
		"BPF_PROG_BIND_MAP support", probe_prog_bind_map,
	},
	[FEAT_MODULE_BTF] = {
		"module BTF support", probe_module_btf,
	},
	[FEAT_BTF_FLOAT] = {
		"BTF_KIND_FLOAT support", probe_kern_btf_float,
	},
	[FEAT_PERF_LINK] = {
		"BPF perf link support", probe_perf_link,
	},
	[FEAT_BTF_DECL_TAG] = {
		"BTF_KIND_DECL_TAG support", probe_kern_btf_decl_tag,
	},
	[FEAT_BTF_TYPE_TAG] = {
		"BTF_KIND_TYPE_TAG support", probe_kern_btf_type_tag,
	},
	[FEAT_MEMCG_ACCOUNT] = {
		"memcg-based memory accounting", probe_memcg_account,
	},
	[FEAT_BPF_COOKIE] = {
		"BPF cookie support", probe_kern_bpf_cookie,
	},
	[FEAT_BTF_ENUM64] = {
		"BTF_KIND_ENUM64 support", probe_kern_btf_enum64,
	},
	[FEAT_SYSCALL_WRAPPER] = {
		"Kernel using syscall wrapper", probe_kern_syscall_wrapper,
	},
	[FEAT_UPROBE_MULTI_LINK] = {
		"BPF multi-uprobe link support", probe_uprobe_multi_link,
	},
};

bool feat_supported(struct kern_feature_cache *cache, enum kern_feature_id feat_id)
{
	struct kern_feature_desc *feat = &feature_probes[feat_id];
	int ret;

	/* assume global feature cache, unless custom one is provided */
	if (!cache)
		cache = &feature_cache;

	if (READ_ONCE(cache->res[feat_id]) == FEAT_UNKNOWN) {
		ret = feat->probe();
		if (ret > 0) {
			WRITE_ONCE(cache->res[feat_id], FEAT_SUPPORTED);
		} else if (ret == 0) {
			WRITE_ONCE(cache->res[feat_id], FEAT_MISSING);
		} else {
			pr_warn("Detection of kernel %s support failed: %d\n", feat->desc, ret);
			WRITE_ONCE(cache->res[feat_id], FEAT_MISSING);
		}
	}

	return READ_ONCE(cache->res[feat_id]) == FEAT_SUPPORTED;
}
