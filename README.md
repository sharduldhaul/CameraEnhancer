# CameraEnhancer
A RAW camera pipeline for Apple silicon built from hand-written Metal compute kernels: classical ISP stages plus a learned raw denoiser, measured for image quality, speed against the GPU's limits, and stability across a test matrix.

See [docs/GOAL.md](docs/GOAL.md) for the goal, success criteria, and engineering process.

## Python environment

Python is used only for training, reference implementations and reports. It is managed with [uv](https://docs.astral.sh/uv/): Python 3.12 is pinned in `.python-version` and package versions are locked in `uv.lock`.

```sh
uv sync          # create .venv with the locked versions
uv run pytest    # run the tests in python/tests
```
