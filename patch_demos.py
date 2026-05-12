import os
import glob

# The SA-ASM snippet to add print_wrapper if not present
wrapper_snippet = """
@ffi_wrapper print_wrapper(&msg: ptr, len: i64) -> void:
    raw_msg = *msg
    call @sys_print(*raw_msg, len)
    return
"""

# The SA-ASM snippet to print "OK\n"
print_snippet = """
    msg = alloc 3
    store msg+0, 79 as i8
    store msg+1, 75 as i8
    store msg+2, 10 as i8
    len = add 3, 0
    call @print_wrapper(&msg, len)
    !len
    !msg
"""

def patch_saasm(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    if "print_wrapper" in content:
        return # Already patched

    # Prepend wrapper
    content = wrapper_snippet + "\n" + content
    
    # Insert print logic before "code = add 0, 0" and "return code"
    lines = content.split('\n')
    out_lines = []
    for line in lines:
        if "code = add 0, 0" in line:
            out_lines.append(print_snippet)
        out_lines.append(line)
        
    with open(filepath, 'w') as f:
        f.write('\n'.join(out_lines))

def patch_rust(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    if "print!" in content:
        return
        
    lines = content.split('\n')
    out_lines = []
    for line in lines:
        if line.strip() == "}":
            if "main" in content and len(out_lines) > 0 and out_lines[-1].strip() != "}":
                # only patch main's closing brace, assuming it's the last one for these simple demos
                pass
        out_lines.append(line)
        
    # a better way: just insert print!("OK\\n"); before the last closing brace
    # assuming the last closing brace is main's
    idx = len(out_lines) - 1
    while idx >= 0:
        if out_lines[idx].strip() == "}":
            out_lines.insert(idx, '    print!("OK\\n");')
            break
        idx -= 1
        
    with open(filepath, 'w') as f:
        f.write('\n'.join(out_lines))

# Patch 02 to 10
for i in range(2, 11):
    pattern = f"demos/rosetta/{i:02d}_*/*"
    for filepath in glob.glob(pattern):
        if filepath.endswith('.saasm'):
            patch_saasm(filepath)
        elif filepath.endswith('.rs'):
            patch_rust(filepath)

print("Patching complete.")
