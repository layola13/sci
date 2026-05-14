# 219 - Pkg Bin Multiple

This demo shows a package-shaped tree with two sibling bin modules and a shared aggregate entry.

```text
demos/rosetta/219_pkg_bin_multiple/
├── main.saasm
├── readme.md
├── sa.pkg
└── bin/
    ├── index.saasm
    ├── alpha/
    │   ├── index.saasm
    │   └── helpers/
    │       ├── index.saasm
    │       └── alpha.saasm-layout
    └── beta/
        ├── index.saasm
        └── helpers/
            ├── index.saasm
            └── beta.saasm-layout
```

`main.saasm` compiles. `sa.pkg` is future metadata only.
