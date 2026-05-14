# 220 - Pkg Lib Dynamic

This demo splits the package into a host tree and a library tree. The host consumes the ABI declared in `lib/iface.saasm-iface`, while the library side keeps its implementation in `lib/impl/index.saasm` and exports the ABI from `lib/index.saasm`.

```text
demos/rosetta/220_pkg_lib_dynamic/
├── main.saasm
├── readme.md
├── sa.pkg
├── host/
│   ├── index.saasm
│   └── helpers/
│       ├── index.saasm
│       └── host.saasm-layout
└── lib/
    ├── iface.saasm-iface
    ├── index.saasm
    └── impl/
        ├── index.saasm
        └── helpers/
            ├── index.saasm
            └── lib.saasm-layout
```

`main.saasm` compiles against the host-side ABI only. `sa.pkg` is future metadata only.
