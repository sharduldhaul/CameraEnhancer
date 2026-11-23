#!/usr/bin/env bash
# Creates the milestones and task issues for CameraEnhancer. The plan lives in docs/GOAL.md.
#
# Usage:
#   DRY_RUN=1 ./create_issues.sh           # print what would be created, no GitHub calls
#   ./create_issues.sh                     # create missing milestones and issues
#   UPDATE_EXISTING=1 ./create_issues.sh   # also rewrite the body and milestone of existing issues
#
# The script is idempotent: a milestone or issue whose title already exists is not created again.
# Each task is one issue (label: task) with a goal and a done-when checklist.
set -euo pipefail

REPO="sharduldhaul/CameraEnhancer"
DRY_RUN="${DRY_RUN:-0}"
UPDATE_EXISTING="${UPDATE_EXISTING:-0}"
CREATED=0

if [ "$DRY_RUN" != "1" ]; then
  gh auth status >/dev/null
fi

# ---------------------------------------------------------------- helpers

label() { # name color description
  if [ "$DRY_RUN" = "1" ]; then echo "label: $1"; return; fi
  gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force >/dev/null
}

milestone() { # title description [due_on, ISO 8601]
  if [ "$DRY_RUN" = "1" ]; then echo; echo "milestone: $1${3:+ (due $3)}"; return; fi
  local existing
  existing=$(gh api "repos/$REPO/milestones?state=all&per_page=100" \
    --jq ".[] | select(.title == \"$1\") | .number")
  if [ -n "$existing" ]; then
    echo; echo "milestone exists: $1"
    return
  fi
  if [ -n "${3:-}" ]; then
    gh api --method POST "repos/$REPO/milestones" -f title="$1" -f description="$2" -f due_on="$3" >/dev/null
  else
    gh api --method POST "repos/$REPO/milestones" -f title="$1" -f description="$2" >/dev/null
  fi
  echo; echo "milestone created: $1"
}

task() { # milestone title ; body on stdin
  local body
  body=$(cat)
  if [ "$DRY_RUN" = "1" ]; then echo "  $2"; return; fi
  local existing
  existing=$(gh issue list --repo "$REPO" --state all --limit 500 --json number,title \
    --jq ".[] | select(.title == \"$2\") | .number")
  if [ -n "$existing" ]; then
    if [ "$UPDATE_EXISTING" = "1" ]; then
      printf '%s\n' "$body" | gh issue edit "$existing" --repo "$REPO" \
        --milestone "$1" --add-label task --body-file - >/dev/null
      echo "  updated #$existing $2"
    else
      echo "  exists  #$existing $2"
    fi
    return
  fi
  local url
  url=$(printf '%s\n' "$body" | gh issue create --repo "$REPO" --milestone "$1" --label task \
    --title "$2" --body-file -)
  CREATED=$((CREATED + 1))
  echo "  created #${url##*/} $2"
}

# ---------------------------------------------------------------- labels

label task "5319e7" "One task: a goal and a done-when checklist"

# ---------------------------------------------------------------- v0.1

M="v0.1 Classical pipeline"
milestone "$M" \
  "Three ISP kernels turn a 12 MP Bayer frame into an sRGB image. Timed, checked against library references, and compared with Apple's CIRAWFilter." \
  "2026-12-07T23:59:59Z"

task "$M" "T01 Build" <<'EOF'
## Goal
One command compiles the C++ host code and the Metal kernels. `libce` holds the GPU code and `ce` is a thin command-line program on top of it. See the library design rules in `docs/GOAL.md` and the scope in `docs/tasks/scaffold-build/README.md`.

## Done when
- [ ] `xcrun -sdk macosx metal --version` succeeds. Toolchain versions are recorded in the README.
- [ ] metal-cpp is vendored in `third_party/metal-cpp`, pinned to one release.
- [ ] `cmake -B build && cmake --build build` produces `libce`, `ce` and `build/kernels.metallib` with zero warnings under `-Wall -Wextra -Werror`.
- [ ] Editing a `.metal` file rebuilds `kernels.metallib`.
- [ ] `ce` prints the GPU name.
- [ ] `.clang-format` is committed and `clang-format --dry-run --Werror` passes.

**Dates:** Nov 22–24
EOF

task "$M" "T02 GPU harness and timing" <<'EOF'
## Goal
Load kernels from `kernels.metallib`, dispatch them with one call, and time them on the GPU. Dispatch follows library design rules 2 and 3: it encodes into a command buffer the caller provides and uses buffers the caller provides.

## Done when
- [ ] A context object owns `MTL::Device` and `MTL::CommandQueue` through `NS::SharedPtr`.
- [ ] A pipeline cache creates one pipeline per function name from `kernels.metallib`. An unknown name produces a clear error.
- [ ] Dispatch encodes into a command buffer passed in by the caller.
- [ ] A copy kernel matches its input exactly for sizes 1, 1023, 2^20, and a size that is not a multiple of the threadgroup size.
- [ ] Timing reads `gpuStartTime` and `gpuEndTime`, discards warm-up runs, and reports median, p10 and p90.
- [ ] Three runs of a 256 MB copy give medians within 5% of each other.

**Dates:** Nov 25–27
EOF

task "$M" "T03 Bandwidth ceiling" <<'EOF'
## Goal
Measure the real memory bandwidth of this GPU. It is the ceiling for every memory-bound stage (S3).

## Done when
- [ ] A `float4` copy kernel passes verification.
- [ ] A sweep from 1 MB to 512 MB writes a CSV with buffer size and GB/s. GB/s counts bytes read plus bytes written.
- [ ] Peak sustained GB/s is saved in `results/device.json` with the chip, the macOS version and Apple's published 120 GB/s.

**Cut 1** (if T01–T03 are not merged by Nov 29): measure one 256 MB buffer instead of a sweep.

**Dates:** Nov 28
EOF

task "$M" "T04 Test data and references" <<'EOF'
## Goal
Provide the input data and the library references that every kernel is checked against (S1).

## Done when
- [ ] A 12 MP Bayer RAW file is chosen, for example from raw.pixls.us. Its source and license are recorded in `data/README.md`. The file itself is not committed.
- [ ] An export script uses `rawpy` to write the Bayer plane (uint16) and a metadata JSON file: width, height, CFA pattern, black level, white level, white balance gains and color matrix.
- [ ] References: Normalize uses NumPy, Demosaic uses `colour-demosaicing` (bilinear), and Color and tone uses `colour-science`.
- [ ] The file format and the `ce` command that the tests call are documented.
- [ ] A pytest harness runs `ce` on the exported data and compares each stage with its reference. Tolerances are documented.

**Dates:** Nov 25–29
EOF

task "$M" "T05 Normalize kernel" <<'EOF'
## Goal
The first ISP kernel. It subtracts the black level, scales by the white level, and applies the white balance gain for each CFA position.

## Done when
- [ ] Pseudocode is reviewed before the Metal code is written.
- [ ] The stage can be called on its own through `libce` (library design rule 4).
- [ ] The output matches the NumPy reference within the documented fp32 tolerance.
- [ ] Achieved GB/s and % of the T03 ceiling are reported.

**Dates:** Nov 30
EOF

task "$M" "T06 Demosaic kernel" <<'EOF'
## Goal
Bilinear demosaic. It computes the two missing colors at every pixel from its Bayer neighbors.

## Done when
- [ ] Pseudocode, including border handling, is reviewed before the Metal code is written.
- [ ] The stage can be called on its own through `libce`.
- [ ] The output matches `colour-demosaicing` bilinear within the documented tolerance, borders included.
- [ ] Achieved GB/s and % of the T03 ceiling are reported.

**Dates:** Dec 1–2
EOF

task "$M" "T07 Color and tone kernel" <<'EOF'
## Goal
Convert camera RGB to sRGB. The kernel applies a 3×3 color matrix, clips to [0, 1], and encodes with the sRGB transfer function.

## Done when
- [ ] Pseudocode is reviewed before the Metal code is written.
- [ ] The stage can be called on its own through `libce`.
- [ ] The output matches `colour-science` within the documented tolerance.
- [ ] Achieved GB/s and % of the T03 ceiling are reported.

**Cut 2** (if T01–T03 are not merged by Nov 29): use a gamma curve instead of the exact sRGB function.

**Dates:** Dec 3
EOF

task "$M" "T08 Pipeline, benchmark and baseline" <<'EOF'
## Goal
Chain the three stages, measure them, and measure Apple's `CIRAWFilter` on the same input.

## Done when
- [ ] A `libce` pipeline object chains Normalize, Demosaic, and Color and tone in one command buffer. `ce run` uses it.
- [ ] `ce bench` writes a results JSON with per-stage and total GPU time (median of 20 runs after warm-up), GB/s, % of ceiling, chip, OS and commit.
- [ ] The full pipeline takes ≤ 33 ms of GPU time on the 12 MP frame (S2).
- [ ] A Swift script times `CIRAWFilter` on the same file with lens correction off, noise reduction at 0, and the same output size. It reports the median of 20 `CIRenderInfo.kernelExecutionTime` values (S4).
- [ ] One command regenerates the README results table from the results JSON (S5).

**Dates:** Dec 4–5
EOF

task "$M" "Release v0.1" <<'EOF'
## Goal
Publish the v0.1 results and promote `develop` to `main`.

## Done when
- [ ] The README shows the results table: GPU time per stage and in total, % of the bandwidth ceiling, and `CIRAWFilter` time.
- [ ] S1–S5 in `docs/GOAL.md` are checked, and any miss is written up.
- [ ] A PR from `develop` to `main` carries the results and is merged.
- [ ] `main` is tagged `v0.1`.

**Cut 3** (if T01–T03 are not merged by Nov 29): drop the per-stage % of ceiling from the table and keep the total time against `CIRAWFilter`.

**Dates:** Dec 6–7
EOF

# ---------------------------------------------------------------- later milestones (tasks are created when each one starts)

milestone "v0.2 Learned denoiser" \
  "Small CNN trained in PyTorch on SIDD. Inference on hand-written Metal convolution kernels: naive, tiled, then simdgroup_matrix. Compared with Core ML and MPSGraph on the same weights."

milestone "v0.3 Library release" \
  "Swift package, Core Image wrapper (CIImageProcessorKernel), iOS build, API documentation."

milestone "v0.4 Characterization" \
  "Compute ceiling and roofline report, threadgroup size sweeps, test matrix (ISO, scenes, thermal state), regression check, sensor noise characterization, CI on a self-hosted runner."

echo
echo "Issues created: $CREATED"
