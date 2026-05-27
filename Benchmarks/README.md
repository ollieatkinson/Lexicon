# Benchmarks

Document performance benchmarks live in a separate Swift package so regular `swift test` runs stay focused on correctness and do not build the benchmarking toolchain.

Run the benchmark suite from this directory:

```sh
swift package benchmark --target LexiconBenchmarks --no-progress --scale --time-units milliseconds
```

Install jemalloc first if allocator metrics are needed:

```sh
brew install jemalloc
```

Set `BENCHMARK_DISABLE_JEMALLOC=1` when jemalloc is unavailable.
