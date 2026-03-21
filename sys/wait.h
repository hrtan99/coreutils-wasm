#ifndef COREUTILS_WASI_SYS_WAIT_H
#define COREUTILS_WASI_SYS_WAIT_H

#ifdef __wasi__

#include <errno.h>
#include <sys/types.h>

#define WIFEXITED(status) 1
#define WIFSIGNALED(status) 0
#define WEXITSTATUS(status) ((status) & 0xff)
#define WTERMSIG(status) ((status) & 0x7f)
#define WNOHANG 1

static inline pid_t
waitpid (pid_t pid, int *status, int options)
{
  errno = ENOSYS;
  return -1;
}

#else

# include_next <sys/wait.h>

#endif

#endif
