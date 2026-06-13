#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>

typedef int (*pthread_create_fn)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
typedef int (*pthread_join_fn)(pthread_t, void **);
typedef int (*pthread_detach_fn)(pthread_t);

static void *lookup_pthread_symbol(const char *name) {
    void *symbol = dlvsym(RTLD_NEXT, name, "GLIBC_2.34");
    if (symbol != 0) return symbol;
    symbol = dlvsym(RTLD_NEXT, name, "GLIBC_2.2.5");
    if (symbol != 0) return symbol;
    return dlsym(RTLD_NEXT, name);
}

int sa_host_pthread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*start_routine)(void *), void *arg) {
    pthread_create_fn fn = (pthread_create_fn)lookup_pthread_symbol("pthread_create");
    if (fn == 0) return 22;
    return fn(thread, attr, start_routine, arg);
}

int sa_host_pthread_join(pthread_t thread, void **retval) {
    pthread_join_fn fn = (pthread_join_fn)lookup_pthread_symbol("pthread_join");
    if (fn == 0) return 22;
    return fn(thread, retval);
}

int sa_host_pthread_detach(pthread_t thread) {
    pthread_detach_fn fn = (pthread_detach_fn)lookup_pthread_symbol("pthread_detach");
    if (fn == 0) return 22;
    return fn(thread);
}
