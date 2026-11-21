lines = open("src/emit_js.zig").read().split("\n")

# writeRuntimeHeader writeAll string: lines 147..900 (1-based).
# Split at line 525 (start of __sa_cvt_bitcast_f64i).
# Part A: 147..524, Part B: 525..900.
# Verify boundaries.
assert lines[145].strip().startswith("try writer.writeAll("), lines[145]
assert lines[900].strip() == ");", lines[900]
assert lines[524].strip().startswith("\\\\function __sa_cvt_bitcast_f64i"), lines[524]
print("boundaries OK")
print(f"line 147: {lines[146][:60]}")
print(f"line 524: {lines[523][:60]}")
print(f"line 525: {lines[524][:60]}")
print(f"line 900: {lines[899][:60]}")

part_a = lines[146:524]   # 0-based 146..523 = 1-based 147..524
part_b = lines[524:900]   # 0-based 524..899 = 1-based 525..900
print(f"part A: {len(part_a)} lines, part B: {len(part_b)} lines")

header = "// JS runtime header chunk (moved from src/emit_js.zig writeRuntimeHeader).\n// Pure data: the emitted JS source text for the runtime header.\n"
pa = ["pub const header_runtime_js_a ="] + part_a + [";"]
pb = ["pub const header_runtime_js_b ="] + part_b + [";"]
open("src/emit_js/runtime_header_a.zig", "w").write(header + "\n".join(pa) + "\n")
open("src/emit_js/runtime_header_b.zig", "w").write(header + "\n".join(pb) + "\n")
print("wrote runtime_header_a.zig and runtime_header_b.zig")

# Replace the writeAll block (lines 146..901, 0-based 145..900) in emit_js.zig.
# The writeAll block is lines[145:901] (0-based), i.e. 1-based 146..901.
replacement = [
    '    try writer.writeAll(@import("emit_js/runtime_header_a.zig").header_runtime_js_a);',
    '    try writer.writeAll("\\n");',
    '    try writer.writeAll(@import("emit_js/runtime_header_b.zig").header_runtime_js_b);',
]
lines[145:901] = replacement
open("src/emit_js.zig", "w").write("\n".join(lines))
print("replaced writeAll block with two-part write")
print("done")
