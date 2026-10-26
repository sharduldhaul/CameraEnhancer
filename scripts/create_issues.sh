#!/usr/bin/env bash
# Creates labels, milestones, task issues and sub-issues for CameraEnhancer.
#
# Usage:
#   DRY_RUN=1 ./create_issues.sh   # print what would be created, no GitHub calls
#   ./create_issues.sh             # create everything on GitHub
#
# Structure:
#   Milestone -> Task issue (label: task)
#     Sub-issues X.1 to X.5 (label: design): goal, expected outcome,
#       entities + ER diagram, OO mapping, task guidelines
#     Sub-issues X.6+ (label: impl): implementation steps
set -euo pipefail

REPO="sharduldhaul/CameraEnhancer"
DRY_RUN="${DRY_RUN:-0}"
API_VERSION="2022-11-28"
LAST=""
FAKE=0
COUNT=0

if [ "$DRY_RUN" != "1" ]; then
  gh auth status >/dev/null
fi

# ---------------------------------------------------------------- helpers

label() { # name color description
  if [ "$DRY_RUN" = "1" ]; then echo "label: $1"; return; fi
  gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force >/dev/null
}

milestone() { # title description
  if [ "$DRY_RUN" = "1" ]; then echo; echo "milestone: $1"; return; fi
  local existing
  existing=$(gh api "repos/$REPO/milestones?state=all&per_page=100" \
    --jq ".[] | select(.title == \"$1\") | .number")
  if [ -z "$existing" ]; then
    gh api --method POST "repos/$REPO/milestones" -f title="$1" -f description="$2" >/dev/null
  fi
}

new_issue() { # milestone label title ; body on stdin ; sets LAST to issue number
  COUNT=$((COUNT + 1))
  if [ "$DRY_RUN" = "1" ]; then
    cat >/dev/null
    FAKE=$((FAKE + 1)); LAST="$FAKE"
    if [ "$2" = "task" ]; then echo "  #$LAST $3"; else echo "      #$LAST [$2] $3"; fi
    return
  fi
  local url
  url=$(gh issue create --repo "$REPO" --milestone "$1" --label "$2" --title "$3" --body-file -)
  LAST="${url##*/}"
}

link() { # parent_number child_number
  if [ "$DRY_RUN" = "1" ]; then return; fi
  local child_id
  child_id=$(gh api "repos/$REPO/issues/$2" --jq .id)
  gh api --method POST "repos/$REPO/issues/$1/sub_issues" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: $API_VERSION" \
    -F sub_issue_id="$child_id" >/dev/null
}

design() { # milestone parent tid slug
  local ms="$1" p="$2" t="$3" d="docs/tasks/$4"

  new_issue "$ms" design "$t.1 Define the goal" <<EOF
Parent: #$p

Write the **Goal** section of \`$d/README.md\`:
- Problem this task solves and why the lab needs it
- In scope
- Out of scope

**Done when:** the section is committed and agrees with the goal in #$p.
EOF
  link "$p" "$LAST"

  new_issue "$ms" design "$t.2 Define the expected outcome" <<EOF
Parent: #$p

Write the **Expected outcome** section of \`$d/README.md\`:
- Acceptance criteria, each one measurable
- Failure criteria: which results mean stop and rethink
- How each criterion is verified (test, benchmark, or review)

**Done when:** every criterion has a verification method.
EOF
  link "$p" "$LAST"

  new_issue "$ms" design "$t.3 Map entities and relationships" <<EOF
Parent: #$p

Write \`$d/entities.md\`:
- Entities this task introduces or touches (data and runtime objects)
- Attributes of each entity
- Relationships with cardinality
- A Mermaid \`erDiagram\` of the above

**Done when:** the diagram renders on GitHub and covers every entity listed.
EOF
  link "$p" "$LAST"

  new_issue "$ms" design "$t.4 Map entities to C++ types" <<EOF
Parent: #$p

Write \`$d/classes.md\`:
- Each entity mapped to a C++ class or struct
- Ownership and lifetime of each type (value, \`std::unique_ptr\`, \`NS::SharedPtr\`)
- Public interface of each type
- A Mermaid \`classDiagram\`

If this task adds no new types, write \`Not applicable\` with the reason and close this issue.

**Done when:** every entity from $t.3 has a type or a stated reason for having none.
EOF
  link "$p" "$LAST"

  new_issue "$ms" design "$t.5 Write task guidelines" <<EOF
Parent: #$p

Write \`$d/guidelines.md\` with rules specific to this task, extending \`docs/GUIDELINES.md\`.
(T01 creates \`docs/GUIDELINES.md\` in this step.)

Cover:
- Naming
- Error handling
- Resource ownership
- Numeric tolerances
- Test requirements
- Benchmark method (warmup, iterations, statistic reported)

**Done when:** reviewed before the first implementation commit of #$p.
EOF
  link "$p" "$LAST"
}

impl() { # milestone parent tid index "Title :: done-when"
  local title="${5%% :: *}" done_when="${5#* :: }"
  new_issue "$1" impl "$3.$4 $title" <<EOF
Parent: #$2

**Done when:** $done_when

Follow \`docs/GUIDELINES.md\` and the task guidelines from $3.5.
EOF
  link "$2" "$LAST"
}

task() { # milestone tid slug title goal expected impl_items...
  local ms="$1" tid="$2" slug="$3" title="$4" goal="$5" expected="$6"
  shift 6
  new_issue "$ms" task "$tid $title" <<EOF
## Goal
$goal

## Expected outcome
$expected

## Process
Design sub-issues $tid.1 to $tid.5 close before implementation sub-issues start.
Design docs live in \`docs/tasks/$slug/\`.
EOF
  local parent="$LAST" i=6 item
  design "$ms" "$parent" "$tid" "$slug"
  for item in "$@"; do
    impl "$ms" "$parent" "$tid" "$i" "$item"
    i=$((i + 1))
  done
}

# ---------------------------------------------------------------- labels

label task   "5319e7" "Top-level task with design and implementation sub-issues"
label design "0e8a16" "Design step: goal, outcome, entities, types, guidelines"
label impl   "1d76db" "Implementation step"

# ---------------------------------------------------------------- M0

M="M0 Foundation"
milestone "$M" "Project builds, Metal toolchain works, device properties reported."

task "$M" T01 scaffold-build "Project scaffold and build" \
  'Create a C++20 project that compiles host code with metal-cpp and compiles `.metal` sources into a `.metallib` loaded at runtime.' \
  'A clean `cmake -B build && cmake --build build` produces the `ce` binary and `kernels.metallib` with zero warnings under `-Wall -Wextra -Werror`.' \
  'Verify Metal toolchain :: `xcrun -sdk macosx metal --version` succeeds. If the toolchain is missing, install it with `xcodebuild -downloadComponent MetalToolchain`. Versions recorded in README.' \
  'CMake skeleton :: CMakeLists.txt builds an empty `ce` executable with C++20 and warnings as errors.' \
  'Vendor metal-cpp :: Headers pinned to one release in `third_party/metal-cpp`. One translation unit defines `NS_PRIVATE_IMPLEMENTATION` and `MTL_PRIVATE_IMPLEMENTATION`. Links the Metal and Foundation frameworks.' \
  'Kernel library build step :: CMake custom command compiles `kernels/*.metal` to `.air` and links them into `build/kernels.metallib`. Editing a `.metal` file triggers a rebuild.' \
  'Formatting and lint config :: `.clang-format` and `.clang-tidy` committed. `clang-format --dry-run --Werror` passes on all sources.'

task "$M" T02 device-info "Device introspection" \
  'Report the GPU properties that bound kernel design on this Mac.' \
  '`ce info` prints device name, unified memory flag, recommended max working set size, max threads per threadgroup, max threadgroup memory, and highest supported Apple GPU family. The same data is written as JSON.' \
  'Device query :: `ce info` prints the listed properties from `MTL::Device`.' \
  'GPU family detection :: Reports the highest `MTL::GPUFamilyApple*` for which `supportsFamily` returns true.' \
  'JSON output :: `ce info --json` writes `results/device.json`. Schema documented in `docs/tasks/device-info/`.'

# ---------------------------------------------------------------- M1

M="M1 Harness"
milestone "$M" "Kernels dispatch, time, and verify through one reusable layer."

task "$M" T03 dispatch "Buffer and dispatch layer" \
  'Provide owning wrappers for device, command queue, buffers, and compute pipelines so a kernel dispatches with one call.' \
  'A `vector_add` kernel runs through the layer and matches the CPU result exactly for sizes 1, 1023, 1048576, and a size that is not a multiple of the threadgroup size.' \
  'Context object :: Owns `MTL::Device` and `MTL::CommandQueue` through `NS::SharedPtr`. No raw `release()` calls outside wrappers.' \
  'Typed buffers :: Shared-storage buffers expose a typed CPU view (`std::span`). Size is checked at creation.' \
  'Pipeline cache :: One pipeline per function name, created from `kernels.metallib` and reused. A missing function name produces a clear error.' \
  'Dispatch API :: One call sets pipeline, buffers, grid size, and threadgroup size, then commits and waits. Command buffer errors are surfaced to the caller.' \
  'vector_add smoke kernel :: Passes all sizes listed in the parent issue.'

task "$M" T04 timing "GPU timing" \
  'Measure kernel execution time on the GPU with stable, repeatable statistics.' \
  'Timing uses command buffer `GPUStartTime` and `GPUEndTime`, runs warmup iterations, and reports median, p10, and p90. Three back-to-back runs of a 256 MB copy report medians within 5% of each other.' \
  'Timer :: Returns per-iteration GPU time from command buffer timestamps.' \
  'Warmup and iteration control :: Warmup count and iteration count are configurable. Warmup results are discarded.' \
  'Statistics :: Median, p10, p90, and min reported. Unit tested on fixed inputs.' \
  'Repeatability check :: Result of the 5% test documented, with notes on thermal state and background load.'

task "$M" T05 correctness "Correctness verification" \
  'Verify every kernel against a CPU reference before any benchmark result is accepted.' \
  '`ctest` runs all correctness tests. fp32 and fp16 comparisons use documented absolute and relative tolerances. The benchmark path refuses to report timing for a kernel that fails verification.' \
  'Test framework :: Framework chosen in design, integrated with CMake and `ctest`.' \
  'CPU reference library :: Reference implementations live in their own module, separate from kernel host code.' \
  'Tolerance compare :: Compares fp32 and fp16 outputs. Reports max absolute error, max relative error, and first failing index.' \
  'Benchmark gate :: Benchmark path runs verification first and aborts on failure.'

# ---------------------------------------------------------------- M2

M="M2 Memory bandwidth"
milestone "$M" "Measured bandwidth ceiling for memory-bound kernels."

task "$M" T06 bandwidth "Bandwidth probe" \
  'Measure the real memory bandwidth ceiling of this GPU. It becomes the roofline limit for memory-bound kernels.' \
  'Read, write, and copy kernels sweep buffer sizes from 1 MB to 512 MB. Results report GB/s per size. Peak sustained bandwidth is stored in `results/device.json` and compared with the Apple published figure for the chip.' \
  'Copy kernel :: Scalar and `float4` variants, both verified.' \
  'Read-only kernel :: Reduction that the compiler cannot eliminate, verified.' \
  'Write-only kernel :: Fill kernel, verified.' \
  'Size sweep :: Sweeps 1 MB to 512 MB per buffer. Outputs CSV with columns size, variant, GB/s.' \
  'Peak record :: Highest sustained GB/s saved as the bandwidth ceiling, with chip name and macOS version.'

# ---------------------------------------------------------------- M3

M="M3 FP16 matvec"
milestone "$M" "Optimized fp16 matrix-vector kernels compared with the bandwidth ceiling and MLX."

task "$M" T07 matvec-f16 "FP16 matrix-vector kernels" \
  'Implement the decode-path matrix-vector multiply in progressively optimized variants and measure each against the bandwidth ceiling.' \
  'Variants v1 to v4 pass verification on shapes 4096x4096, 14336x4096, and 4096x14336 (rows x cols). Target: best variant reaches at least 70% of measured bandwidth. Failure criterion: below 50% requires a written analysis before M4 starts.' \
  'Variant v1 :: One thread per row. Verified and timed.' \
  'Variant v2 :: One threadgroup per row with threadgroup-memory reduction. Verified and timed.' \
  'Variant v3 :: Simdgroup reduction with `simd_sum`. Verified and timed.' \
  'Variant v4 :: v3 with `half4` vectorized loads. Verified and timed.' \
  'Shape sweep :: CSV with columns variant, shape, median time, effective GB/s.'

task "$M" T08 mlx-baseline "MLX baseline" \
  'Measure MLX on the same shapes to know the gap between the hand-written kernels and a production library.' \
  '`bench/baselines/mlx_matvec.py` times fp16 matvec for the T07 shapes, synchronizing with `mx.eval`. Results use the T07 CSV schema. Comparison table committed in `docs/tasks/mlx-baseline/`.' \
  'Baseline script :: Uses the same warmup and iteration counts as the C++ harness.' \
  'Schema match :: Output CSV has the same columns as the C++ results.' \
  'Comparison table :: Per shape: best own variant, MLX, ratio.'

# ---------------------------------------------------------------- M4

M="M4 Quantized matvec"
milestone "$M" "4-bit weights with dequantization fused into the kernel."

task "$M" T09 q4-format "Q4 block format" \
  'Define a 4-bit weight format and CPU quantize and dequantize routines that the GPU kernel reads.' \
  'Format documented byte by byte: blocks of 32 weights, one fp16 scale, 16 bytes of packed 4-bit values, 18 bytes per block (same layout as llama.cpp Q4_0). CPU round-trip error measured and recorded.' \
  'Format spec :: Layout, nibble order, and alignment documented.' \
  'CPU quantize :: Produces blocks from fp32 weights. Unit tested.' \
  'CPU dequantize :: Inverse routine. Round-trip RMSE recorded for random weights.'

task "$M" T10 matvec-q4 "Q4 matrix-vector kernel with fused dequantization" \
  'Multiply a Q4 weight matrix by an fp16 vector, dequantizing inside the kernel.' \
  'Kernel matches CPU dequantize plus matvec within documented tolerance on the T07 shapes. Effective bandwidth is computed from Q4 bytes read. Target: at least 2x faster than the best fp16 variant on 14336x4096.' \
  'Fused kernel v1 :: One simdgroup per row. Verified and timed.' \
  'Fused kernel v2 :: Vectorized block loads and simdgroup reduction. Verified and timed.' \
  'Comparison :: CSV and table against the best fp16 variant.'

# ---------------------------------------------------------------- M5

M="M5 Characterization"
milestone "$M" "Roofline, pipeline limits, and occupancy explain each result."

task "$M" T11 characterization "Kernel characterization and roofline" \
  'Identify why each kernel performs as it does: compute-bound or memory-bound, pipeline limits, and threadgroup sizing.' \
  'For every kernel variant the report lists arithmetic intensity, achieved GB/s and GFLOP/s, position on a roofline built from measured ceilings, pipeline properties, and the limiting factor.' \
  'Compute ceiling probe :: FMA-heavy kernel measures peak fp32 and fp16 GFLOP/s.' \
  'Pipeline properties :: `threadExecutionWidth`, `maxTotalThreadsPerThreadgroup`, and `staticThreadgroupMemoryLength` recorded per pipeline in results JSON.' \
  'Threadgroup size sweep :: For each kernel, time versus threadgroup size. Best size recorded.' \
  'Counter support survey :: Records which counter sets and sampling points this GPU supports.' \
  'GPU trace capture :: `ce capture --kernel <name>` writes a `.gputrace` through `MTL::CaptureManager` (run with `MTL_CAPTURE_ENABLED=1`). One trace opened in Xcode with findings noted.'

# ---------------------------------------------------------------- M6

M="M6 Complete program"
milestone "$M" "One CLI runs tests, benchmarks, reports, and regression checks."

task "$M" T12 cli-suite "CLI and benchmark suite" \
  'Expose every capability through one CLI so the full test and benchmark run is one command.' \
  'Subcommands `info`, `test`, `bench`, `suite`, `capture`, `compare`. `ce suite` runs verification then benchmarks for all kernels and writes one JSON file with chip, macOS version, git commit, and build type.' \
  'Argument parsing :: Subcommands and flags documented in `--help`.' \
  'Kernel registry :: Each kernel registers name, shapes, CPU reference, and dispatch. The CLI discovers kernels from the registry.' \
  'Suite runner :: Runs all registered kernels behind the verification gate.' \
  'Environment metadata :: Captured in every results file.'

task "$M" T13 report-regression "Report and regression check" \
  'Turn results into a readable report and detect performance regressions between commits.' \
  '`scripts/report.py` generates a Markdown report with tables and a roofline chart from suite JSON. `ce compare old.json new.json` exits nonzero when any kernel median slows by more than 10%. Runs locally on this Mac so timings stay comparable.' \
  'Report generator :: Markdown tables and roofline PNG from suite JSON.' \
  'Compare command :: Nonzero exit code on regression. Threshold configurable.' \
  'Baseline file :: Reference results committed with the environment they came from.'

echo
echo "Issues created: $COUNT"
