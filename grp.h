#ifndef COREUTILS_WASI_GRP_H
#define COREUTILS_WASI_GRP_H

#ifdef __wasi__

#include <errno.h>
#include <stddef.h>
#include <sys/types.h>

struct group
{
  char *gr_name;
  char *gr_passwd;
  gid_t gr_gid;
  char **gr_mem;
};

static inline struct group *
getgrnam (const char *name)
{
  errno = ENOSYS;
  return NULL;
}

static inline struct group *
getgrgid (gid_t gid)
{
  errno = ENOSYS;
  return NULL;
}

static inline int
getgrnam_r (const char *name, struct group *grp,
            char *buf, size_t buflen, struct group **result)
{
  errno = ENOSYS;
  if (result)
    *result = NULL;
  return ENOSYS;
}

static inline int
getgrgid_r (gid_t gid, struct group *grp,
            char *buf, size_t buflen, struct group **result)
{
  errno = ENOSYS;
  if (result)
    *result = NULL;
  return ENOSYS;
}

static inline struct group *
getgrent (void)
{
  errno = ENOSYS;
  return NULL;
}

static inline void
setgrent (void)
{
}

static inline void
endgrent (void)
{
}

static inline int
getgrouplist (const char *user, gid_t group, gid_t *groups, int *ngroups)
{
  errno = ENOSYS;
  return -1;
}

#else

# include_next <grp.h>

#endif

#endif
