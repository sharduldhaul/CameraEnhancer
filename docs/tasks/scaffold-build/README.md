# T01 Project scaffold and build

Parent issue: #1. Project goal: [docs/GOAL.md](../../GOAL.md).

## Goal

### Problem

Every stage of the camera pipeline, from the first ISP kernel to the denoiser's convolutions, is a Metal Shading Language kernel called from C++ host code. Nothing can be built, tested or timed until one command compiles both. T01 provides that command: a C++20 project that compiles host code with metal-cpp and compiles `.metal` sources into a `.metallib` that the host loads at runtime.

### Why the lab needs it

- **Comparable results.** Benchmarks from different commits are only comparable when the build is fixed: one compiler, one set of flags, one pinned metal-cpp release.
- **Errors at build time.** Compiling `.metal` sources ahead of time reports shader errors during the build instead of at runtime. It also keeps shader compilation out of measured GPU time.
- **A target for CI.** The CI gate in [docs/GOAL.md](../../GOAL.md#engineering-process) needs a build that fails on warnings, format errors and lint errors.

### In scope

- Check the Metal toolchain and record its version in the README.
- CMake project that builds the `mkl` executable as C++20 with `-Wall -Wextra -Werror`.
- metal-cpp vendored in `third_party/metal-cpp`, pinned to one release, linked with the Metal and Foundation frameworks.
- Build step that compiles `kernels/*.metal` into `build/kernels.metallib` and rebuilds when a `.metal` file changes.
- One placeholder kernel, so the build step has an input.
- `.clang-format` and `.clang-tidy` configuration.

### Out of scope

- Loading the `.metallib` and dispatching kernels (T03).
- Device queries (T02), timing (T04), correctness tests (T05).
- Python environment for training, references and reports.
- CI workflows. They are a separate task, and T01 only provides the build they call.
