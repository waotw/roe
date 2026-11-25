/*
 * A stand-in for C23's <stdckdint.h>, for Macs whose compiler hasn't got it.
 *
 * mise's ready-made macOS Rubies are built on the newest macOS, so their
 * headers include <stdckdint.h>. macOS 14's Command Line Tools (Apple
 * clang 16) don't ship it, and without it no gem with C code builds. The
 * Gemfile puts this directory on CPATH only in that case. The compiler's
 * __builtin_*_overflow functions do the same job as the C23 macros.
 */
#ifndef ROE_COMPAT_STDCKDINT_H
#define ROE_COMPAT_STDCKDINT_H

#define ckd_add(result, a, b) __builtin_add_overflow((a), (b), (result))
#define ckd_sub(result, a, b) __builtin_sub_overflow((a), (b), (result))
#define ckd_mul(result, a, b) __builtin_mul_overflow((a), (b), (result))

#endif
