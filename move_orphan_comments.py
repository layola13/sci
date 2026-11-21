#!/usr/bin/env python3
"""Move comment blocks that precede alias lines in sa_std.zig to the
submodule where the fn is defined (inserted before the fn definition),
then delete them from sa_std.zig. This preserves the documentation in
its correct place (with the code it documents).

Only handles alias lines OUTSIDE the re-exports section (the section's
own // --- headers are structural, not doc comments).
"""
import re, os

sa_path = "src/runtime/sa_std.zig"
lines = open(sa_path).read().split("\n")

# find the re-exports section bounds to skip it
re_start = next((i for i, l in enumerate(lines) if l.startswith("// Re-exports:")), None)
re_end = None
if re_start is not None:
    j = re_start
    while j < len(lines):
        l = lines[j]
        if l.strip().startswith("//") or ("pub const " in l and "@import(" in l) or l.strip() == "":
            j += 1
        else:
            break
    re_end = j

alias_re = re.compile(r'pub const ([A-Za-z0-9_]+) = @import\("([^"]+)"\)\.\1;')
# cache submodule file contents
sub_cache = {}

def load_sub(modpath):
    # modpath is relative to src/runtime/ (e.g. sa_std/text_util.zig)
    full = os.path.join("src/runtime", modpath)
    if full not in sub_cache:
        sub_cache[full] = open(full).read().split("\n")
    return sub_cache[full]

moved_blocks = 0
moved_lines = 0
# process from bottom so line numbers stay valid
i = len(lines) - 1
while i >= 0:
    l = lines[i]
    if re_start is not None and re_start <= i < re_end:
        i -= 1
        continue
    if "@import(" in l and "pub const " in l:
        m = alias_re.search(l)
        if m:
            name, mod = m.group(1), m.group(2)
            # walk back over preceding comment lines and blanks
            j = i - 1
            cmt_lines = []
            k = j
            while k >= 0 and (lines[k].strip().startswith("//") or lines[k].strip() == ""):
                if lines[k].strip().startswith("//"):
                    cmt_lines.append(lines[k])
                k -= 1
            # cmt_lines are in reverse order; only proceed if there's a
            # contiguous comment block directly above (allow 1 blank line)
            if cmt_lines:
                cmt_lines.reverse()
                # find the fn definition in the target submodule
                sub = load_sub(mod)
                # find the decl line for name (not an alias/import line)
                decl_re = re.compile(rf"^(?:pub\s+)?(?:export\s+)?(?:threadlocal\s+)?(?:const|fn|var)\s+{re.escape(name)}\b")
                di = None
                for t, sl in enumerate(sub):
                    if "@import(" in sl:
                        continue
                    if decl_re.match(sl):
                        di = t
                        break
                if di is not None:
                    # insert the comment block before the decl (with a blank line after)
                    sub[di:di] = cmt_lines + [""]
                    moved_blocks += 1
                    moved_lines += len(cmt_lines)
                    # delete the comment lines from sa_std.zig (from k+1 to i-1, only comment lines)
                    # remove comment lines in range (k+1 .. i-1), keep blanks collapsed later
                    del lines[k + 1:i]
                    # adjust i (we deleted lines before it)
                    i = k + 1
                    continue
    i -= 1

for full, sub in sub_cache.items():
    open(full, "w").write("\n".join(sub))
open(sa_path, "w").write("\n".join(lines))
print(f"moved {moved_blocks} comment blocks ({moved_lines} lines) to submodules")
print(f"sa_std.zig now {len(lines)} lines")
