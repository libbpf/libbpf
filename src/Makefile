# SPDX-License-Identifier: (LGPL-2.1 OR BSD-2-Clause)

TOPDIR = ..
INCLUDES = -I. -I$(TOPDIR)/include -I$(TOPDIR)/include/uapi
CFLAGS = $(INCLUDES) -O2 -Werror -Wall

FEATURE_REALLOCARRAY := $(shell $(TOPDIR)/scripts/check-reallocarray.sh)
ifneq ($(FEATURE_REALLOCARRAY),)
  CFLAGS += -DCOMPAT_NEED_REALLOCARRAY
endif

OBJFILES = bpf.o btf.o libbpf.o libbpf_errno.o netlink.o nlattr.o str_error.o

all: libbpf.a

libbpf.a: $(OBJFILES)
	/bin/rm -f $@; /bin/ar rcs $@ $^

%.o: %.c
	gcc $(CFLAGS) -c $< -o $@

clean:
	/bin/rm -f libbpf.a $(OBJFILES)
