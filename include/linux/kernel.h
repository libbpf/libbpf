/* SPDX-License-Identifier: (LGPL-2.1 OR BSD-2-Clause) */

#ifndef __LINUX_KERNEL_H
#define __LINUX_KERNEL_H

#define offsetof(TYPE, MEMBER) ((size_t) &((TYPE *)0)->MEMBER)

#define container_of(ptr, type, member) ({                      \
        const typeof(((type *)0)->member) * __mptr = (ptr);     \
        (type *)((char *)__mptr - offsetof(type, member)); })

#endif
