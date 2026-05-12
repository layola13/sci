#ifndef SA_LIBSA_SCOPE_H
#define SA_LIBSA_SCOPE_H

#ifdef __cplusplus
extern "C" {
#endif

void *scope_new(void);
void scope_drop(void *tracker);
void scope_enter(void *tracker);
void scope_exit(void *tracker);
void scope_bind(void *tracker, const char *reg_name);
void scope_move(void *tracker, const char *reg_name);
void scope_release(void *tracker, const char *reg_name);
void scope_branch_begin(void *tracker);
void scope_branch_add_path(void *tracker);
void scope_branch_merge(void *tracker);
const char *scope_emit_releases(void *tracker);

#ifdef __cplusplus
}
#endif

#endif
