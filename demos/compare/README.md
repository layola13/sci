# SA vs Rust Compare Benchmarks

This directory contains reproducible comparison workloads. The scripts report median timings across repeated runs and keep compile time separate from runtime.

## Workloads

- `big_bench.*`: many small functions and direct calls. This stresses frontend scaling, symbol management, verifier work, LLVM lowering, and link time.
- `bench.*`: equivalent `sum += i * i` loop work in SA and Rust. This is the runtime sanity benchmark.
- `thread_bench.*`: thread spawn/join model benchmark. This measures the SA `pthread_*` ABI path against Rust `std::thread` for the same tiny workload.
- `macro_hell.*`: macro-heavy ECS-like expansion pressure. Keep this reported separately from the ordinary big/loop benchmarks because it is intentionally adversarial to Rust macro and borrow-check paths.

## Running

```sh
python3 demos/compare/gen_big.py
RUNS=3 bash demos/compare/run_sa_bench.sh
RUNS=3 bash demos/compare/run_rust_bench.sh
RUNS=3 bash demos/compare/run_sa_parallel_bench.sh
RUNS=3 bash demos/compare/run_thread_bench.sh
```

The SA benchmark must use a release-built compiler. `run_sa_bench.sh` builds `zig-out/bin/sa` with `zig build -Doptimize=ReleaseFast` by default before timing benchmark workloads. Do not compare Rust `-C opt-level=3` against a Debug SA compiler.

For the current big benchmark, `run_sa_bench.sh` defaults to `JOBS=1` because the current CGU path does extra repeated work and is slower on this workload. That is a compiler implementation detail, not a benchmark requirement.

Use `run_sa_parallel_bench.sh` to track that implementation detail separately. It runs the same SA big benchmark across `JOBS_LIST` values, defaulting to `1 2 3 4 auto`, and reports each profile independently.

`run_thread_bench.sh` is a separate benchmark because it is not the same thing as the main compile benchmark. It measures a real SA `pthread_spawn` / `pthread_join` workload against Rust `std::thread` on the same chunked CPU loop.

Useful knobs:

- `RUNS=N`: number of repetitions used for median timing.
- `JOBS=auto|N`: SA compiler job setting for `run_sa_bench.sh`.
- `JOBS_LIST="1 2 3 4 auto"`: SA job settings for `run_sa_parallel_bench.sh`.
- `BUILD_RELEASE=0`: skip rebuilding the SA compiler, only when `SA_BIN` already points at a release binary.
- `SA_BIN=/path/to/sa`: SA compiler binary.
- `RUSTC=/path/to/rustc`: Rust compiler binary.

## Interpreting Results

Do not collapse these scenarios into one headline. A valid report should show at least:

- big compile time
- loop compile time
- loop runtime
- executable size
- SA phase profile JSON from `--profile --json`

Current known issue: the big benchmark is still dominated by SA frontend verification work on large generated files. Treat that as an optimization target, not as an already-won benchmark.
