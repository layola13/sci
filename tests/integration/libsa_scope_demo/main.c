#include "libsa_scope.h"

#include <stdio.h>

int main(void) {
    void *scope = scope_new();
    if (scope == NULL) {
        return 91;
    }

    scope_bind(scope, "root");
    scope_enter(scope);
    scope_bind(scope, "temp");
    scope_exit(scope);
    fputs(scope_emit_releases(scope), stdout);

    scope_branch_begin(scope);
    scope_branch_add_path(scope);
    scope_move(scope, "root");
    scope_branch_add_path(scope);
    scope_branch_merge(scope);
    fputs(scope_emit_releases(scope), stdout);

    scope_drop(scope);
    return 0;
}
