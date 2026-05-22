import os
import re

def fix_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Replace any ../sa_std/ or ../../../sa_std/ with just sa_std/
    new_content = re.sub(r'(?:\.\./)+sa_std/', 'sa_std/', content)
    
    if new_content != content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Fixed {filepath}")

for root, dirs, files in os.walk('.'):
    if '.git' in root or 'zig-cache' in root or 'zig-out' in root or '.codex' in root or '.kiro' in root:
        continue
    for file in files:
        if file.endswith(('.sa', '.sai', '.sal', '.zig', '.md')):
            fix_file(os.path.join(root, file))
