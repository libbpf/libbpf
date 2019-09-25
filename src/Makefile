# SPDX-License-Identifier: (LGPL-2.1 OR BSD-2-Clause)

LIBBPF_VERSION := $(shell \
	grep -oE '^LIBBPF_([0-9.]+)' libbpf.map | \
	sort -rV | head -n1 | cut -d'_' -f2)
LIBBPF_MAJOR_VERSION := $(firstword $(subst ., ,$(LIBBPF_VERSION)))

TOPDIR = ..

INCLUDES := -I. -I$(TOPDIR)/include -I$(TOPDIR)/include/uapi
ALL_CFLAGS := $(INCLUDES)

FEATURE_REALLOCARRAY := $(shell $(TOPDIR)/scripts/check-reallocarray.sh)
ifneq ($(FEATURE_REALLOCARRAY),)
	ALL_CFLAGS += -DCOMPAT_NEED_REALLOCARRAY
endif

ifndef BUILD_STATIC_ONLY
	ALL_CFLAGS += -fPIC -fvisibility=hidden
endif

CFLAGS ?= -g -O2 -Werror -Wall
ALL_CFLAGS += $(CFLAGS)
ALL_LDFLAGS += $(LDFLAGS)
ifdef NO_PKG_CONFIG
	ALL_LDFLAGS += -lelf
else
	PKG_CONFIG ?= pkg-config
	ALL_CFLAGS += $(shell $(PKG_CONFIG) --cflags libelf)
	ALL_LDFLAGS += $(shell $(PKG_CONFIG) --libs libelf)
endif

OBJDIR ?= .

OBJS := $(addprefix $(OBJDIR)/,bpf.o btf.o libbpf.o libbpf_errno.o netlink.o \
	nlattr.o str_error.o libbpf_probes.o bpf_prog_linfo.o xsk.o \
	btf_dump.o hashmap.o)

LIBS := $(OBJDIR)/libbpf.a
ifndef BUILD_STATIC_ONLY
	LIBS += $(OBJDIR)/libbpf.so \
		$(OBJDIR)/libbpf.so.$(LIBBPF_MAJOR_VERSION) \
		$(OBJDIR)/libbpf.so.$(LIBBPF_VERSION)
	VERSION_SCRIPT := libbpf.map
endif

HEADERS := bpf.h libbpf.h btf.h xsk.h libbpf_util.h
UAPI_HEADERS := $(addprefix $(TOPDIR)/include/uapi/linux/,bpf.h bpf_common.h \
	btf.h)

PC_FILE := $(OBJDIR)/libbpf.pc

INSTALL = install

DESTDIR ?=

ifeq ($(shell uname -m),x86_64)
	LIBSUBDIR := lib64
else
	LIBSUBDIR := lib
endif

PREFIX ?= /usr
LIBDIR ?= $(PREFIX)/$(LIBSUBDIR)
INCLUDEDIR ?= $(PREFIX)/include
UAPIDIR ?= $(PREFIX)/include

all: $(LIBS) $(PC_FILE)

$(OBJDIR)/libbpf.a: $(OBJS)
	$(AR) rcs $@ $^

$(OBJDIR)/libbpf.so: $(OBJDIR)/libbpf.so.$(LIBBPF_MAJOR_VERSION)
	ln -sf $(^F) $@

$(OBJDIR)/libbpf.so.$(LIBBPF_MAJOR_VERSION): $(OBJDIR)/libbpf.so.$(LIBBPF_VERSION)
	ln -sf $(^F) $@

$(OBJDIR)/libbpf.so.$(LIBBPF_VERSION): $(OBJS)
	$(CC) -shared -Wl,--version-script=$(VERSION_SCRIPT) \
		      -Wl,-soname,libbpf.so.$(LIBBPF_MAJOR_VERSION) \
		      $^ $(ALL_LDFLAGS) -o $@

$(OBJDIR)/libbpf.pc:
	sed -e "s|@PREFIX@|$(PREFIX)|" \
		-e "s|@LIBDIR@|$(LIBDIR)|" \
		-e "s|@VERSION@|$(LIBBPF_VERSION)|" \
		< libbpf.pc.template > $@

$(OBJDIR)/%.o: %.c
	$(CC) $(ALL_CFLAGS) $(CPPFLAGS) -c $< -o $@

define do_install
	if [ ! -d '$(DESTDIR)$2' ]; then		\
		$(INSTALL) -d -m 755 '$(DESTDIR)$2';	\
	fi;						\
	$(INSTALL) $1 $(if $3,-m $3,) '$(DESTDIR)$2'
endef

# Preserve symlinks at installation.
define do_s_install
	if [ ! -d '$(DESTDIR)$2' ]; then		\
		$(INSTALL) -d -m 755 '$(DESTDIR)$2';	\
	fi;						\
	cp -fpR $1 '$(DESTDIR)$2'
endef

install: all install_headers install_pkgconfig
	$(call do_s_install,$(LIBS),$(LIBDIR))

install_headers:
	$(call do_install,$(HEADERS),$(INCLUDEDIR)/bpf,644)

# UAPI headers can be installed by a different package so they're not installed
# in by install rule.
install_uapi_headers:
	$(call do_install,$(UAPI_HEADERS),$(UAPIDIR)/linux,644)

install_pkgconfig: $(PC_FILE)
	$(call do_install,$(PC_FILE),$(LIBDIR)/pkgconfig,644)

clean:
	rm -f *.o *.a *.so *.so.* *.pc
