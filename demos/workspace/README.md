# SA Workspace Demo

This demo exercises native `sa.mod` workspace support in `sci`.

Run from this directory:

```bash
/home/vscode/projects/sci/zig-out/bin/sa install
/home/vscode/projects/sci/zig-out/bin/sa build-exe -o app_demo
/home/vscode/projects/sci/zig-out/bin/sa build-exe -p tool -o tool_demo
```

The workspace root defaults to the `app` member. `-p tool` selects the `tool` member without passing a source file path.
