# Easy SynthSR (TUI)

Brain MRI segmentation pipeline for macOS (Apple Silicon) and Linux (GPU/HPC).

Runs **SynthSR → SynthSeg** as the default path, with **FastSurfer** as an optional step for confirmed 3D T1 acquisitions.

**macOS (ARM64)**: SynthSeg runs natively via Python (`synthseg-metal` conda env).
**Linux (GPU)**: SynthSeg runs inside a Docker container.

> 한국어 문서: [README.KO.md](README.KO.md)

---

## Why This Exists

I just wanted to run SynthSR.

I opened the FreeSurfer docs and found the installation guide. I figured I'd follow the steps — but the binaries didn't work on macOS ARM64. Docker seemed like a reasonable workaround. SynthSR under x86 emulation was slow. Since I was already using Docker, I bundled SynthSeg in a container too. Then it bothered me that I couldn't use the GPU on Apple Silicon. I decided to run it natively with tensorflow-metal. I set up a fresh conda environment. The 3D BatchNorm layers didn't support Metal FusedBN, so it fell back to CPU. Still 1.36× faster than Docker emulation. Once SynthSeg was working, I figured I'd wire in FastSurfer too.

Five scripts. Five scripts means you forget the order. So I wrote a pipeline script. Then a TUI.

**All of this because of SynthSR.**

---

## Pipeline Overview

```
DICOM → NIfTI → [select] → SynthSR → SynthSeg → (FastSurfer)
  [10]    [10]     [20]       [30]       [40]         [50]
```

| Step | Script | Tool | Notes |
|------|--------|------|-------|
| DICOM → NIfTI | `10_dicom2nifti.sh` | dcm2niix | Cached; skipped if NIfTI exists |
| Select NIfTI | `20_select_nifti.sh` | nibabel | Blacklist + 2D/thick-slice auto-exclusion |
| SynthSR | `30_synthsr.sh` | freesurfer/freesurfer | Super-resolution; `--cpu` on Mac |
| SynthSeg (Mac) | `40_synthseg_native.sh` | tensorflow-metal + SynthSeg | ARM64 native, 1.36× faster than Docker |
| SynthSeg (Linux) | `40_synthseg.sh` | pwesp/synthseg (Docker) | GPU support |
| FastSurfer | `50_fastsurfer.sh` | deepmi/fastsurfer | Optional; header safety check before run |

`90_pipeline.sh` automatically switches Step 40 based on `COMPOSE_OS`.

---

## Requirements

### Common

| Tool | Mac | Linux |
|------|-----|-------|
| dcm2niix | `brew install dcm2niix` | system package or container |
| python3 + nibabel | `pip install nibabel` | recommended |
| FreeSurfer license | `license.txt` | same |

### macOS (ARM64) — native SynthSeg

| Item | Notes |
|------|-------|
| miniforge (arm64) | [Install miniforge](https://github.com/conda-forge/miniforge) |
| conda env `synthseg-metal` | auto-configured via `bash scripts/setup_tf_metal_env.sh` |

```bash
# One-time setup
bash scripts/setup_tf_metal_env.sh
```

### Linux — Docker

| Item | Notes |
|------|-------|
| Docker Desktop / Engine | required |

---

## Quick Start

### 1. Configure `.env`

```bash
cp .env.example .env
```

Edit `.env`:

```bash
DATA_ROOT=/path/to/data   # project data root
SID=subjectX              # subject ID
FS_LICENSE_DIR=/path/to/freesurfer/license
FS_LICENSE_FILE=license.txt
THREADS=4
```

### 2. Place DICOM files

```
data/
└── dicom/
    └── subjectX/    ← put DICOM files here
```

### 3. (Mac only) Set up native SynthSeg environment

```bash
bash scripts/setup_tf_metal_env.sh
```

### 4. Run

```bash
# Interactive TUI (recommended)
./easy-synthseg

# Direct script — macOS ARM64
./scripts/90_pipeline.sh

# Direct script — Linux GPU
COMPOSE_OS=linux ./scripts/90_pipeline.sh
```

The pipeline is interactive: it shows NIfTI candidates, prompts for selection, and asks whether to run FastSurfer at the end.

---

## Output Structure

```
data/
├── dicom/subjectX/                    # original DICOM (input)
├── nifti/subjectX/                    # dcm2niix output
├── derivatives/subjectX/
│   ├── synthsr/
│   │   └── subjectX_synthsr.nii.gz    # SynthSR result
│   ├── synthseg/
│   │   ├── subjectX_synthseg.nii.gz   # SynthSeg segmentation
│   │   └── subjectX_synthseg_vols.csv # region volumes
│   └── fastsurfer/                    # FastSurfer result (if run)
└── logs/subjectX/
    └── selected_input.txt             # reproducibility record
```

---

## Running Individual Steps

Each script can be run independently. All scripts load `.env` automatically.

```bash
./scripts/00_env_check.sh           # check dependencies
./scripts/10_dicom2nifti.sh         # DICOM → NIfTI
./scripts/20_select_nifti.sh        # select input file
./scripts/30_synthsr.sh             # run SynthSR
./scripts/40_synthseg_native.sh     # run SynthSeg (Mac ARM64, default)
./scripts/40_synthseg.sh            # run SynthSeg (Docker fallback)
./scripts/50_fastsurfer.sh          # run FastSurfer (optional)
```

### Cache / Force re-run

```bash
FORCE=1 ./scripts/30_synthsr.sh
FORCE=1 ./scripts/40_synthseg_native.sh
FORCE_CONVERT=1 ./scripts/10_dicom2nifti.sh
```

---

## Mac vs Linux

| `COMPOSE_OS` | Step 40 | Platform | GPU |
|---|---|---|---|
| `mac` (default) | `40_synthseg_native.sh` | ARM64 native | Metal (CPU fallback) |
| `linux` | `40_synthseg.sh` (Docker) | native | NVIDIA GPU |

### macOS SynthSeg Performance

| Method | Avg. Runtime | Notes |
|--------|:------------:|-------|
| Docker x86 emulation (old) | 398.7s ± 4.9s | Rosetta emulation |
| Native ARM64 (current default) | 292.3s ± 4.9s | **1.36× faster** |

> tensorflow-metal detects the Metal GPU, but SynthSeg's 3D BatchNorm falls back to CPU
> due to missing Metal FusedBN support. Output NIfTI is 100% identical to Docker results (max diff = 0.0000).

---

## NIfTI Candidate Selection

`20_select_nifti.sh` filters candidates using two passes:

**1. Blacklist** (always applied):

```
dwi, dti, adc, trace, swi, angio, tof, mra, spine,
localizer, survey, t2, flair, fse, gre, ...
```

**2. Header safety check** (requires nibabel):

- Slices ≤ 30 or voxel z-size ≥ 2.5 mm → excluded from FastSurfer candidates
- Excluded files are listed with a SynthSeg-only recommendation

The selection is recorded in `data/logs/{SID}/selected_input.txt` for reproducibility.

---

## Compose Structure

Docker Compose is used for SynthSR (Step 30), SynthSeg Linux (Step 40), and FastSurfer (Step 50).

```
compose/
├── docker-compose.common.yml    # service definitions (freesurfer, synthseg, fastsurfer)
├── docker-compose.mac.yml       # platform: linux/amd64, user: 0:0
└── docker-compose.linux-gpu.yml # GPU reservation
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `[ERR] DICOM directory not found` | `data/dicom/{SID}/` missing | Create directory and place DICOM files |
| `[ERR] SynthSR output not found` | Step 30 not yet run | Run `30_synthsr.sh` first |
| `[ERR] FS license not found` | Wrong `FS_LICENSE_DIR` or `FS_LICENSE_FILE` | Check `.env` and file path |
| `[ERR] conda env 'synthseg-metal' not found` | env not configured | Run `bash scripts/setup_tf_metal_env.sh` |
| `[ERR] run_native_test.py not found` | `synthseg_src/` not installed | Re-run `scripts/setup_tf_metal_env.sh` |
| `[WARN] nibabel not found` | python3-nibabel not installed | `pip install nibabel` (optional but recommended) |
| FastSurfer OOM on Mac | 2D or thick-slice input | Use SynthSeg result instead; skip FastSurfer |
| Slow SynthSR on Mac | amd64 emulation on ARM | Expected; use for single-case validation only |

---

## FreeSurfer License

SynthSR (Step 30) and FastSurfer (Step 50) require a valid FreeSurfer license file.

1. Register for free at https://surfer.nmr.mgh.harvard.edu/registration.html
2. Place the issued `license.txt` in `FS_LICENSE_DIR`
3. Set `FS_LICENSE_DIR` and `FS_LICENSE_FILE` in `.env`

---

## Project Structure

```
easy-synthseg/
├── easy-synthseg                 # TUI entry point (run with ./easy-synthseg)
├── .env                          # local config (not committed)
├── .env.example                  # template
├── compose/
│   ├── docker-compose.common.yml
│   ├── docker-compose.mac.yml
│   └── docker-compose.linux-gpu.yml
├── scripts/
│   ├── _common.sh                # shared env loader + nibabel utilities
│   ├── 00_env_check.sh
│   ├── 10_dicom2nifti.sh
│   ├── 20_select_nifti.sh
│   ├── 30_synthsr.sh
│   ├── 40_synthseg_native.sh     # SynthSeg default (Mac ARM64)
│   ├── 40_synthseg.sh            # SynthSeg Docker fallback (Linux)
│   ├── 50_fastsurfer.sh
│   ├── 90_pipeline.sh
│   ├── setup_tf_metal_env.sh     # one-time Mac native env setup
│   └── tui.py                    # TUI body (Python + Rich)
├── synthseg_src/
│   ├── run_native_test.py        # SynthSeg CLI wrapper (BatchNorm 5D patch)
│   └── SynthSeg/                 # SynthSeg source + weights (not committed)
└── data/                         # input/output data (not committed)
```

---

## License

The wrapper code (scripts, TUI) is released under the **FreeSurfer Software License (v1.0)** — non-commercial research use only. See [LICENSE](LICENSE) for the full text.

| Tool | License |
|------|---------|
| [FreeSurfer](https://surfer.nmr.mgh.harvard.edu) | [FreeSurfer Software License](https://surfer.nmr.mgh.harvard.edu/fswiki/FreeSurferSoftwareLicense) |
| [SynthSR](https://github.com/BBillot/SynthSR) | Apache-2.0 |
| [SynthSeg](https://github.com/BBillot/SynthSeg) | Apache-2.0 |
| [FastSurfer](https://github.com/Deep-MI/FastSurfer) | Apache-2.0 |
