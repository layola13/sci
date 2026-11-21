#!/usr/bin/env python3
"""Add containsCapability and riskLevelName imports to audit_report.zig."""
path = "src/pkg/audit_report.zig"
lines = open(path).read().split("\n")
lines.insert(3, 'const containsCapability = @import("audit.zig").containsCapability;')
lines.insert(4, 'const riskLevelName = @import("audit.zig").riskLevelName;')
open(path, "w").write("\n".join(lines))
print("imports added")
