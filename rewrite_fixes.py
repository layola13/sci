import re

with open('src/runtime/sa_std.zig', 'r') as f:
    content = f.read()

# Change finish and finishErr
content = re.sub(
    r'fn finish\(status: i32\) i32 \{.*?return status;\n\}',
    r'fn finish(status: i32) Fallible(i32) {\n    last_error = status;\n    return .{ .status = status, .value = 0 };\n}',
    content, flags=re.DOTALL
)

content = re.sub(
    r'fn finishErr\(err: anyerror\) i32 \{.*?return finish\(mapError\(err\)\);\n\}',
    r'fn finishErr(err: anyerror) Fallible(i32) {\n    return finish(mapError(err));\n}',
    content, flags=re.DOTALL
)

# Now, any export fn that returns i32 and calls finish() or returns sa_std_close() or similar,
# we need to change its signature to Fallible(i32).

# First, functions that we KNOW should return Fallible(i32):
# We can find all "pub export fn name(...) i32" and change it to Fallible(i32) EXCEPT:
# sa_std_last_error
# Wait, sa_std_last_error returns i32, sa_std_error_name returns i32, wait sa_std_error_name is fallible?
# Let's read the .saasm-iface files to see which ones are NOT fallible.

