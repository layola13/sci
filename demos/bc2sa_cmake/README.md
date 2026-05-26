# bc2sa CMake Demo

This demo is a minimal real C project that builds LLVM bitcode through CMake and Clang, then feeds the `.bc` file into `sa bc2sa`.

## Build bitcode

```sh
cmake -S demos/bc2sa_cmake -B /tmp/bc2sa_cmake_build
cmake --build /tmp/bc2sa_cmake_build --target bc
```

## Translate

```sh
sa bc2sa /tmp/bc2sa_cmake_build/main.bc
```

The output should contain a `demo` function with basic arithmetic, branch, and return lowering.
