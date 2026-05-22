import sys

def gen_rust(n):
    with open("demos/compare/big_bench.rs", "w") as f:
        for i in range(n):
            f.write(f"#[inline(never)]\nfn func_{i}(mut x: Box<i64>) -> Box<i64> {{\n    *x += 1;\n    x\n}}\n\n")
        f.write("fn main() {\n")
        f.write("    let mut x = Box::new(0i64);\n")
        for i in range(n):
            f.write(f"    x = func_{i}(x);\n")
        f.write('    println!("Result: {}", x);\n')
        f.write("}\n")

def gen_sa(n):
    with open("demos/compare/big_bench.sa", "w") as f:
        for i in range(n):
            f.write(f"@func_{i}(^x: ptr) -> ^ptr:\n")
            f.write("L_ENTRY:\n")
            f.write("    r = &x\n")
            f.write("    v = load r+0 as i64\n")
            f.write("    v = add v, 1\n")
            f.write("    store r+0, v as i64\n")
            f.write("    !r\n")
            f.write("    !v\n")
            f.write("    return ^x\n\n")
        f.write("@main():\n")
        f.write("L_ENTRY:\n")
        f.write("    x = alloc 8\n")
        f.write("    store x+0, 0 as i64\n")
        for i in range(n):
            f.write(f"    x = call @func_{i}(^x)\n")
        f.write("    !x\n")
        f.write("    return\n")

n = 10000
gen_rust(n)
gen_sa(n)
print(f"Generated {n} functions in big_bench.rs and big_bench.sa")
