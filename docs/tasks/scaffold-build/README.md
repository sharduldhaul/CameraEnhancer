# T01 Project scaffold and build

Parent issue: #1. Project goal: [docs/GOAL.md](../../GOAL.md).

## Goal

### Problem

Every stage of the camera pipeline, from the first ISP kernel to the denoiser's convolutions, is a Metal Shading Language kernel called from C++ host code. Nothing can be built, tested or timed until one command compiles both. T01 provides that command: a C++20 project that compiles host code with metal-cpp and compiles `.metal` sources into a `.metallib` that the host loads at runtime.

### Why the lab needs it

- **Comparable results.** Benchmarks from different commits are only comparable when the build is fixed: one compiler, one set of flags, one pinned metal-cpp release.
- **Errors at build time.** Compiling `.metal` sources ahead of time reports shader errors during the build instead of at runtime. It also keeps shader compilation out of measured GPU time.
- **A gate for every PR.** The merge checks in [docs/GOAL.md](../../GOAL.md#engineering-process) need a build that fails on warnings and format errors.

### In scope

- Check the Metal toolchain and record its version in the README.
- CMake project that builds the `libce` static library and the `ce` executable on top of it, as C++20 with `-Wall -Wextra -Werror`. See the library design rules in [docs/GOAL.md](../../GOAL.md#library-design-rules).
- metal-cpp vendored in `third_party/metal-cpp`, pinned to one release, linked with the Metal and Foundation frameworks.
- Build step that compiles `kernels/*.metal` into `build/kernels.metallib` and rebuilds when a `.metal` file changes.
- One placeholder kernel, so the build step has an input.
- `ce` creates the default `MTL::Device` and prints its name, which proves metal-cpp links and runs.
- `.clang-format` configuration.

### Out of scope

- Loading the `.metallib`, dispatching kernels and timing (T02).
- Correctness tests (T04).
- `.clang-tidy` and CI workflows (v0.4).
