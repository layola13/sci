import re

with open('tests/unit_framework/support/json_regex.sa', 'r') as f:
    content = f.read()

content = re.sub(
    r'@support_bytes_eq\(&lhs: ptr, lhs_len: u64, &rhs: ptr, rhs_len: u64\) -> i32:',
    r'@support_bytes_eq(&lhs: ptr, lhs_len: u64, *rhs: ptr, rhs_len: u64) -> i32:',
    content
)

with open('tests/unit_framework/support/json_regex.sa', 'w') as f:
    f.write(content)
