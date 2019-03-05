/* SPDX-License-Identifier: (LGPL-2.1 OR BSD-2-Clause) */

#ifndef __LINUX_COMPILER_H
#define __LINUX_COMPILER_H

#define likely(x)		__builtin_expect(!!(x), 1)
#define unlikely(x)		__builtin_expect(!!(x), 0)

#define READ_ONCE(x)		(*(volatile typeof(x) *)&x)
#define WRITE_ONCE(x, v)	(*(volatile typeof(x) *)&x) = (v)

#define barrier()		asm volatile("" ::: "memory")

#if defined(__x86_64__)

# define smp_rmb()		asm volatile("lfence" ::: "memory")
# define smp_wmb()		asm volatile("sfence" ::: "memory")

# define smp_store_release(p, v)		\
do {						\
	barrier();				\
	WRITE_ONCE(*p, v);			\
} while (0)

# define smp_load_acquire(p)			\
({						\
	typeof(*p) ___p = READ_ONCE(*p);	\
	barrier();				\
	___p;					\
})

#else

# define smp_mb()		__sync_synchronize()
# define smp_rmb()		smp_mb()
# define smp_wmb()		smp_mb()

# define smp_store_release(p, v)		\
do {						\
	smp_mb();				\
	WRITE_ONCE(*p, v);			\
} while (0)

# define smp_load_acquire(p)			\
({						\
	typeof(*p) ___p = READ_ONCE(*p);	\
	smp_mb();				\
	___p;					\
})

#endif /* defined(__x86_64__) */
#endif
