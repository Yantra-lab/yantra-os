/*
 * Yantra mini-libc — signal.h
 *
 * A sandboxed module gets no OS signals. Nim's `--os:any` system installs handlers
 * for crash signals at start-up; here that is a no-op that links (a real trap in the
 * sandbox is reported by wasmtime to the host instead).
 */
#ifndef YANTRA_SIGNAL_H
#define YANTRA_SIGNAL_H

#define SIGINT  2
#define SIGILL  4
#define SIGABRT 6
#define SIGFPE  8
#define SIGBUS  7
#define SIGSEGV 11
#define SIG_DFL ((void (*)(int))0)
#define SIG_IGN ((void (*)(int))1)

typedef int sig_atomic_t;
static inline void (*signal(int sig, void (*handler)(int)))(int) { (void)sig; (void)handler; return SIG_DFL; }
static inline int raise(int sig) { (void)sig; return 0; }

#endif
