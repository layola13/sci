import os
import glob
import re

for root, _, files in os.walk('demos'):
    for file in files:
        if file.endswith('.sa') or file.endswith('.sal') or file.endswith('.sai'):
            filepath = os.path.join(root, file)
            with open(filepath, 'r') as f:
                content = f.read()
            
            # We need to replace @import "@/demos/rosetta/XYZ/abc" with relative paths.
            # But the simplest way is just to replace "@/demos/rosetta/XYZ/" with "" 
            # if we are already inside demos/rosetta/XYZ/
            
            # Let's find the current directory relative to project root
            # e.g. demos/rosetta/253_contract_callback_registration
            parts = filepath.split('/')
            
            if 'rosetta' in parts:
                idx = parts.index('rosetta')
                if len(parts) > idx + 1:
                    project_dir = '/'.join(parts[:idx+2]) # e.g. demos/rosetta/253_...
                    
                    # We look for `@import "@/{project_dir}/` and replace with `@import "`
                    pattern = f'@import "@/{project_dir}/'
                    
                    if pattern in content:
                        content = content.replace(pattern, '@import "')
                        with open(filepath, 'w') as f:
                            f.write(content)
                            print(f"Fixed {filepath}")
