#!/usr/bin/env python3
"""Insert import lines into audit_report.zig after line 1 (const std)."""
path = "src/pkg/audit_report.zig"
lines = open(path).read().split("\n")
lines.insert(1, 'const manifest = @import("manifest.zig");')
lines.insert(2, 'const AuditReport = @import("audit.zig").AuditReport;')
open(path, "w").write("\n".join(lines))
print("imports added")
