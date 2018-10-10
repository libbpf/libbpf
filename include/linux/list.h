/* SPDX-License-Identifier: (LGPL-2.1 OR BSD-2-Clause) */

#ifndef __LINUX_LIST_H
#define __LINUX_LIST_H

#define LIST_HEAD_INIT(name) { &(name), &(name) }
#define LIST_HEAD(name) \
        struct list_head name = LIST_HEAD_INIT(name)

#define list_entry(ptr, type, member) \
        container_of(ptr, type, member)
#define list_first_entry(ptr, type, member) \
        list_entry((ptr)->next, type, member)
#define list_next_entry(pos, member) \
        list_entry((pos)->member.next, typeof(*(pos)), member)

#endif
