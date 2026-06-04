# SA (safe asm, 安全汇编)

SA is a low-level safe assembly toolchain built around explicit ownership, a Referee verifier, LLVM-C bitcode emission, WASM output, and a plugin ecosystem. The project keeps `.sa`, `.sai`, and `.sal` as the source/interface/layout formats.

Current implementation notes:

- Core compiler, runtime, standard library, tests, and documentation live in this repository.
- Migrated plugins live in `/home/vscode/projects/sa_plugins/`.
- `tasks.md` is the authoritative task ledger; `docs/progress.md` records the latest completion audit.

## License

This project is open source under the Apache License 2.0; see `LICENSE`. The repository also includes a mandatory `NOTICE` attribution file.

Copyright 2026 zhanhaiyang.

You may use, copy, modify, merge, publish, distribute, sublicense, and sell copies of this work under the Apache License 2.0, provided that every source or binary redistribution retains:

- the copyright notice;
- this license notice;
- the original work name: `SA (safe asm, 安全汇编)`;
- the original author attribution: `zhanhaiyang`;
- any NOTICE text included with the distribution.

Derived works may use their own names, but they must not remove or obscure the original work name and author attribution above.

Apache License 2.0 text: `LICENSE` or https://www.apache.org/licenses/LICENSE-2.0
