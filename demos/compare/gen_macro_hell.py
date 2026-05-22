import sys

def gen_rust(n):
    with open("demos/compare/macro_hell.rs", "w") as f:
        f.write("""// 模拟 Bevy ECS 系统宏展开地狱
macro_rules! define_system {
    ($sys_name:ident, $($comp:ident),*) => {
        #[inline(never)]
        fn $sys_name( $($comp: &mut i64),* ) {
            $(
                *$comp = $comp.wrapping_add(1);
            )*
        }
    }
}
""")
        for i in range(n):
            # 每个 System 查询 10 个不同的可变组件
            f.write(f"define_system!(sys_{i}, c0, c1, c2, c3, c4, c5, c6, c7, c8, c9);\n")
        
        f.write("\nfn main() {\n")
        f.write("    let mut c = [0i64; 10];\n")
        for i in range(n):
            f.write(f"    sys_{i}(&mut c[0], &mut c[1], &mut c[2], &mut c[3], &mut c[4], &mut c[5], &mut c[6], &mut c[7], &mut c[8], &mut c[9]);\n")
        f.write('    println!("Macro Hell Done");\n')
        f.write("}\n")

def gen_sa(n):
    with open("demos/compare/macro_hell.sa", "w") as f:
        f.write("""// 模拟 SA 的文本宏展开
[MACRO] UPDATE_COMP %c, %v
    %v = add %c, 1
    !%c
    !%v
[END_MACRO]

[MACRO] DEFINE_SYSTEM %sys_name
@%sys_name(c0: i64, c1: i64, c2: i64, c3: i64, c4: i64, c5: i64, c6: i64, c7: i64, c8: i64, c9: i64):
L_ENTRY:
    EXPAND UPDATE_COMP c0, v0
    EXPAND UPDATE_COMP c1, v1
    EXPAND UPDATE_COMP c2, v2
    EXPAND UPDATE_COMP c3, v3
    EXPAND UPDATE_COMP c4, v4
    EXPAND UPDATE_COMP c5, v5
    EXPAND UPDATE_COMP c6, v6
    EXPAND UPDATE_COMP c7, v7
    EXPAND UPDATE_COMP c8, v8
    EXPAND UPDATE_COMP c9, v9
    return
[END_MACRO]
""")
        for i in range(n):
            f.write(f"EXPAND DEFINE_SYSTEM sys_{i}\n")
        
        f.write("\n@main():\n")
        f.write("L_ENTRY:\n")
        for i in range(n):
            f.write(f"    call @sys_{i}(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)\n")
        f.write("    return\n")

# 生成 2000 个复杂的系统调用，这足以让 Rust 编译器由于宏展开和借用检查而非常繁忙
n = 2000
gen_rust(n)
gen_sa(n)
print(f"Generated Macro Hell benchmark with {n} systems (10 components each).")
