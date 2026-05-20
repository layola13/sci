import re

with open('tests/unit_framework/support/stdlib_surface.saasm', 'r') as f:
    text = f.read()

# Fix concat_free_status loading payload instead of status
text = text.replace(
    'concat_free_status = load concat_free_res+4 as i32',
    'concat_free_status = load concat_free_res+0 as i32'
)

# Fix loading ptr payloads from +4 to +8 because Fallible(u64) has padding in C ABI!
# Let's find all `load .*+4 as ptr` and replace with +8
text = re.sub(
    r'(load [a-zA-Z0-9_]+)\+4 as ptr',
    r'\1+8 as ptr',
    text
)

# What about u64?
text = re.sub(
    r'(load [a-zA-Z0-9_]+)\+4 as u64',
    r'\1+8 as u64',
    text
)

with open('tests/unit_framework/support/stdlib_surface.saasm', 'w') as f:
    f.write(text)

