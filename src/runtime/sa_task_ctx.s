# sa_std goroutine runtime: x86_64 context primitives.
#
# These three routines are the ONLY hand-written assembly in the
# goroutine runtime. They live in a real assembler file, not in
# Zig naked functions, on purpose: Zig 0.17's self-hosted x86_64
# backend segfaults while linking artifacts in which a naked
# function is reachable from an exported symbol (bisected
# 2026-10-29 on this codebase; the LLVM backend and pure object
# emission are unaffected). Assembler files bypass Zig codegen
# for these routines entirely.
#
# Frame layout expected by sa_task_ctx_switch: the saved stack
# pointer points at 6 pushed callee-saved registers followed by
# the return address:
#   [rsp+0]=r15 [rsp+8]=r14 [rsp+16]=r13 [rsp+24]=r12
#   [rsp+32]=rbx [rsp+40]=rbp [rsp+48]=return address
#
# sa_task_ctx_arm(frame) captures rsp/rip/callee-saved registers
# of its CALLER into the 64-byte RescueFrame (see sa_task.zig):
#   [frame+0]=rsp-after-return [frame+8]=rip
#   [frame+16..56]=r15,r14,r13,r12,rbx,rbp
# It returns 0 when arming; sa_task_ctx_resume(frame, val)
# restores the frame and makes the arm call re-emerge returning
# val. ctx_resume never returns to its own caller.

    .text

    .globl sa_task_ctx_switch
    .type sa_task_ctx_switch, @function
sa_task_ctx_switch:
    push %rbp
    push %rbx
    push %r12
    push %r13
    push %r14
    push %r15
    mov %rsp, (%rdi)
    mov %rsi, %rsp
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
    pop %rbp
    ret
    .size sa_task_ctx_switch, .-sa_task_ctx_switch

    .globl sa_task_ctx_arm
    .type sa_task_ctx_arm, @function
sa_task_ctx_arm:
    mov (%rsp), %rcx
    mov %rcx, 8(%rdi)
    lea 8(%rsp), %rcx
    mov %rcx, 0(%rdi)
    mov %r15, 16(%rdi)
    mov %r14, 24(%rdi)
    mov %r13, 32(%rdi)
    mov %r12, 40(%rdi)
    mov %rbx, 48(%rdi)
    mov %rbp, 56(%rdi)
    xor %eax, %eax
    ret
    .size sa_task_ctx_arm, .-sa_task_ctx_arm

    .globl sa_task_ctx_resume
    .type sa_task_ctx_resume, @function
sa_task_ctx_resume:
    mov 0(%rdi), %rsp
    mov 8(%rdi), %rax
    mov %rax, -8(%rsp)
    mov 16(%rdi), %r15
    mov 24(%rdi), %r14
    mov 32(%rdi), %r13
    mov 40(%rdi), %r12
    mov 48(%rdi), %rbx
    mov 56(%rdi), %rbp
    mov %rsi, %rax
    sub $8, %rsp
    ret
    .size sa_task_ctx_resume, .-sa_task_ctx_resume

    .section .note.GNU-stack,"",@progbits
