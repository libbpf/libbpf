/* SPDX-License-Identifier: (LGPL-2.1 OR BSD-2-Clause) */

#ifndef __LINUX_ERR_H
#define __LINUX_ERR_H

static inline void * ERR_PTR(long error_)
{
        return (void *) error_;
}

#endif
