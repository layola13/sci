#!/usr/bin/env python3
"""Check each domain file for decls that don't match its topic prefix
(overshoot detection: a move that swallowed following decls)."""
import re, glob

expect = {
    "json": "sa_json_", "json_io": "sa_json_", "fs": "sa_fs_", "fs_meta": "sa_fs_",
    "net": "sa_net_", "deno": "sa_deno_", "regex": "sa_regex_", "time": "sa_time_",
    "string": "sa_string_", "env": "sa_env_", "fmt": "sa_fmt_", "io": "sa_io_",
    "str": "sa_str_", "term": "sa_term_", "math": "sa_math_",
    "std_net": "sa_std_net_", "std_net_tcp": "sa_std_net_tcp_",
    "std_net_tcp_stream": "sa_std_net_tcp_stream_", "std_net_udp": "sa_std_net_udp_",
    "std_net_udp_io": "sa_std_net_udp_", "std_net_udp_set": "sa_std_net_udp_",
    "std_net_unix": "sa_std_net_unix_", "std_net_unix_dgram": "sa_std_net_unix_",
    "std_process": "sa_std_process_", "std_process_spawn": "sa_std_process_",
    "std_fs": "sa_std_fs_",
}
for f in sorted(glob.glob("src/runtime/sa_std/*.zig")):
    base = f.split("/")[-1][:-4]
    if base not in expect:
        continue
    txt = open(f).read()
    decls = re.findall(r"^(?:pub\s+)?(?:export\s+)?(?:const|fn|var)\s+([A-Za-z0-9_]+)", txt, re.M)
    # real decls (not import/alias lines)
    real = []
    for d in decls:
        if re.search(r"^const " + re.escape(d) + r" = @import", txt, re.M):
            continue
        if re.search(r"^pub const " + re.escape(d) + r" = @import", txt, re.M):
            continue
        real.append(d)
    bad = [d for d in real if not d.startswith(expect[base]) and d not in ("std", "sa_std")]
    if bad:
        print(base, "UNEXPECTED decls:", bad[:10])
print("check done")
