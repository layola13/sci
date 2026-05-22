# 220 - Pkg Lib Dynamic

This demo splits the package into a host tree and a library tree. The host consumes the ABI declared in `lib/iface.sai`, while the library side keeps its implementation in `lib/impl/index.sa` and exports the ABI from `lib/index.sa`.

```text
demos/rosetta/220_pkg_lib_dynamic/
├── main.sa
├── readme.md
├── sa.pkg
├── host/
│   ├── index.sa
│   └── helpers/
│       ├── index.sa
│       └── host.sal
└── lib/
    ├── iface.sai
    ├── index.sa
    └── impl/
        ├── index.sa
        └── helpers/
            ├── index.sa
            └── lib.sal
```

`main.sa` compiles against the host-side ABI only. `sa.pkg` is future metadata only.
