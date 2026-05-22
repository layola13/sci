# 219 - Pkg Bin Multiple

This demo shows a package-shaped tree with two sibling bin modules and a shared aggregate entry.

```text
demos/rosetta/219_pkg_bin_multiple/
├── main.sa
├── readme.md
├── sa.pkg
└── bin/
    ├── index.sa
    ├── alpha/
    │   ├── index.sa
    │   └── helpers/
    │       ├── index.sa
    │       └── alpha.sal
    └── beta/
        ├── index.sa
        └── helpers/
            ├── index.sa
            └── beta.sal
```

`main.sa` compiles. `sa.pkg` is future metadata only.
