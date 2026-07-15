#include <pthread.h>

/* Keep this import distinct from sa_std's compatibility export named pthread_join. */
extern int sa_system_pthread_join(pthread_t, void **) __asm("_pthread_join$NOCANCEL");

int sa_host_pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                           void *(*start_routine)(void *), void *arg) {
    return pthread_create(thread, attr, start_routine, arg);
}

int sa_host_pthread_join(pthread_t thread, void **retval) {
    return sa_system_pthread_join(thread, retval);
}

int sa_host_pthread_detach(pthread_t thread) {
    return pthread_detach(thread);
}
