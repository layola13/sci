import re

with open('tests/unit_framework/support/json_regex.saasm', 'r') as f:
    text = f.read()

text = re.sub(
    r'(load [a-zA-Z0-9_]+)\+4 as ptr',
    r'\1+8 as ptr',
    text
)

text = re.sub(
    r'(load [a-zA-Z0-9_]+)\+4 as u64',
    r'\1+8 as u64',
    text
)

# And fix any bad free status checks
# Wait, json_regex checks streams... stream_free_status = load stream_free_res+4 as i32
text = text.replace(
    '+4 as i32',
    '+0 as i32'
)

with open('tests/unit_framework/support/json_regex.saasm', 'w') as f:
    f.write(text)

