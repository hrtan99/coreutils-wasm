#ifndef COREUTILS_WASI_PWD_H
#define COREUTILS_WASI_PWD_H

#ifdef __wasi__

#include <errno.h>
#include <stddef.h>
#include <sys/types.h>

struct passwd
{
  char *pw_name;
  char *pw_passwd;
  uid_t pw_uid;
  gid_t pw_gid;
  char *pw_gecos;
  char *pw_dir;
  char *pw_shell;
};

static inline struct passwd *
getpwnam (const char *name)
{
  errno = ENOSYS;
  return NULL;
}

static inline struct passwd *
getpwuid (uid_t uid)
{
  errno = ENOSYS;
  return NULL;
}

static inline int
getpwnam_r (const char *name, struct passwd *pwd,
            char *buf, size_t buflen, struct passwd **result)
{
  errno = ENOSYS;
  if (result)
    *result = NULL;
  return ENOSYS;
}

static inline int
getpwuid_r (uid_t uid, struct passwd *pwd,
            char *buf, size_t buflen, struct passwd **result)
{
  errno = ENOSYS;
  if (result)
    *result = NULL;
  return ENOSYS;
}

#else

# include_next <pwd.h>

#endif

#endif
