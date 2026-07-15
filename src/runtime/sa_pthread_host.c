#define _GNU_SOURCE
#include <dlfcn.h>
#include <pthread.h>

typedef int (*pthread_create_fn)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
typedef int (*pthread_join_fn)(pthread_t, void **);
typedef int (*pthread_detach_fn)(pthread_t);
typedef void *(*dlopen_fn)(const char *, int);
typedef void *(*dlsym_fn)(void *, const char *);
typedef int (*dlclose_fn)(void *);

static void *lookup_host_symbol(const char *name) {
    void *symbol = dlvsym(RTLD_NEXT, name, "GLIBC_2.34");
    if (symbol != 0) return symbol;
    symbol = dlvsym(RTLD_NEXT, name, "GLIBC_2.2.5");
    return symbol;
}

int sa_host_pthread_create(pthread_t *thread, const pthread_attr_t *attr, void *(*start_routine)(void *), void *arg) {
    pthread_create_fn fn = (pthread_create_fn)lookup_host_symbol("pthread_create");
    if (fn == 0) return 22;
    return fn(thread, attr, start_routine, arg);
}

int sa_host_pthread_join(pthread_t thread, void **retval) {
    pthread_join_fn fn = (pthread_join_fn)lookup_host_symbol("pthread_join");
    if (fn == 0) return 22;
    return fn(thread, retval);
}

int sa_host_pthread_detach(pthread_t thread) {
    pthread_detach_fn fn = (pthread_detach_fn)lookup_host_symbol("pthread_detach");
    if (fn == 0) return 22;
    return fn(thread);
}

void *sa_host_dlopen(const char *path, int flags) {
    dlopen_fn fn = (dlopen_fn)lookup_host_symbol("dlopen");
    return fn == 0 ? 0 : fn(path, flags);
}

void *sa_host_dlsym(void *handle, const char *symbol) {
    dlsym_fn fn = (dlsym_fn)lookup_host_symbol("dlsym");
    return fn == 0 ? 0 : fn(handle, symbol);
}

int sa_host_dlclose(void *handle) {
    dlclose_fn fn = (dlclose_fn)lookup_host_symbol("dlclose");
    return fn == 0 ? -1 : fn(handle);
}
