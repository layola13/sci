use std::os::raw::c_int;

#[repr(C)]
struct Context {
    ready: c_int,
    swapped: c_int,
    phase: c_int,
    surface: c_int,
    swap_count: c_int,
}

fn gl_make_current(ctx: &mut Context) -> c_int {
    if ctx.phase == 0 {
        ctx.ready = 1;
        ctx.phase = 1;
        1
    } else {
        0
    }
}

fn gl_swap_buffers(ctx: &mut Context) -> c_int {
    if ctx.phase == 1 {
        ctx.swapped = 1;
        ctx.phase = 2;
        1
    } else {
        0
    }
}

fn main() {
    let mut ctx = Context {
        ready: 0,
        swapped: 0,
        phase: 0,
        surface: 0,
        swap_count: 0,
    };
    let current = gl_make_current(&mut ctx);
    let surface = ctx.surface;
    let swapped = gl_swap_buffers(&mut ctx);
    ctx.swap_count += 1;
    let ok = current == 1 && swapped == 1 && surface == 0 && ctx.swap_count == 1;
    println!("{}", if ok { 1 } else { -1 });
}

