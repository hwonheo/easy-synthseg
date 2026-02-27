# fastsurfer-docker

Brain MRI processing pipeline for macOS (Apple Silicon) and Linux (GPU/HPC).

Runs **SynthSR → SynthSeg** as the default path, with **FastSurfer** as an optional step for confirmed 3D T1 acquisitions.

**macOS (ARM64)**: SynthSeg는 네이티브 Python (`synthseg-metal` conda 환경)으로 직접 실행.
**Linux (GPU)**: SynthSeg는 Docker 컨테이너로 실행.

---

## Why This Exists

SynthSR 하나 돌려보려고 했을 뿐이었다.

FreeSurfer 공식 문서를 열었더니 설치 가이드가 나왔다. 그냥 따라 하면 되겠거니 했는데, macOS ARM64에서 바이너리가 동작하지 않았다. Docker로 우회하면 되겠다고 생각했다. x86 에뮬레이션 위에서 돌아가는 SynthSR은 느렸다. 어차피 Docker 쓰는 김에 SynthSeg도 컨테이너로 묶었다. 그런데 Apple Silicon에서 GPU를 못 쓴다는 게 걸렸다. tensorflow-metal을 써서 네이티브로 돌려보기로 했다. conda 환경을 새로 구성했다. BatchNorm 레이어가 Metal을 지원하지 않아 CPU로 폴백됐다. 그래도 Docker 에뮬레이션보다 1.36배 빨랐다. SynthSeg가 됐으니 FastSurfer도 연결해보자는 생각이 들었다.

스크립트가 다섯 개가 됐다. 스크립트가 다섯 개면 실행 순서를 까먹는다. 그래서 파이프라인 스크립트를 만들었다. 그리고 TUI를 만들었다.

**SynthSR 하나 때문에 이렇게 됐다.**

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
| SynthSeg (Mac) | `40_synthseg_native.sh` | tensorflow-metal + SynthSeg | ARM64 네이티브, 1.36× faster than Docker |
| SynthSeg (Linux) | `40_synthseg.sh` | pwesp/synthseg (Docker) | GPU 지원 |
| FastSurfer | `50_fastsurfer.sh` | deepmi/fastsurfer | Optional; header safety check before run |

`90_pipeline.sh`가 `COMPOSE_OS` 값에 따라 Step 40을 자동 분기합니다.

---

## Requirements

### 공통

| Tool | Mac | Linux |
|------|-----|-------|
| dcm2niix | `brew install dcm2niix` | system package or container |
| python3 + nibabel | `pip install nibabel` | recommended |
| FreeSurfer license | `license.txt` | same |

### macOS (ARM64) — SynthSeg 네이티브 실행 추가 요구사항

| 항목 | 비고 |
|------|------|
| miniforge (arm64) | [miniforge 설치](https://github.com/conda-forge/miniforge) |
| conda env `synthseg-metal` | `bash scripts/setup_tf_metal_env.sh` 로 자동 구성 |

```bash
# conda 환경 1회 구성 (처음 한 번만)
bash scripts/setup_tf_metal_env.sh
```

### Linux — Docker 추가 요구사항

| 항목 | 비고 |
|------|------|
| Docker Desktop / Engine | required |

---

## Quick Start

### 1. Configure `.env`

```bash
cp .env.example .env
```

Edit `.env`:

```bash
DATA_ROOT=/path/to/fastsurfer-docker/data   # project data root
SID=subjectX                                # subject ID
FS_LICENSE_DIR=/path/to/freesurfer/license  # directory containing license.txt
FS_LICENSE_FILE=license.txt
THREADS=4
```

### 2. Place DICOM files

```bash
data/
└── dicom/
    └── subjectX/    ← put DICOM files here
```

### 3. (Mac only) Set up native SynthSeg environment

```bash
# 처음 한 번만 실행
bash scripts/setup_tf_metal_env.sh
```

### 4. Run the full pipeline

```bash
# Interactive TUI (recommended)
./easy-synthseg

# Direct script (macOS ARM64 default — native SynthSeg)
./scripts/90_pipeline.sh

# Linux with GPU — Docker SynthSeg
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
│   │   └── subjectX_synthseg_vols.csv # region volumes (parcellation)
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
# Force re-run (overwrite output)
FORCE=1 ./scripts/30_synthsr.sh
FORCE=1 ./scripts/40_synthseg_native.sh

# Force DICOM re-conversion
FORCE_CONVERT=1 ./scripts/10_dicom2nifti.sh
```

---

## Mac vs Linux

`COMPOSE_OS` 변수로 Step 40 분기 및 Docker Compose override를 제어합니다:

| `COMPOSE_OS` | Step 40 | Platform | GPU |
|---|---|---|---|
| `mac` (default) | `40_synthseg_native.sh` | ARM64 네이티브 | Metal (CPU fallback) |
| `linux` | `40_synthseg.sh` (Docker) | native | NVIDIA GPU |

```bash
# Linux GPU 환경에서 실행
COMPOSE_OS=linux ./scripts/90_pipeline.sh
```

### macOS SynthSeg 성능

| 방식 | 평균 처리 시간 | 비고 |
|------|:-------------:|------|
| Docker x86 emulation (이전) | 398.7s ± 4.9s | Rosetta 에뮬레이션 |
| Native ARM64 (현재 기본값) | 292.3s ± 4.9s | **1.36× 빠름** |

> tensorflow-metal이 Metal GPU를 인식하나, SynthSeg의 3D BatchNorm이 Metal FusedBN 미지원으로
> CPU 모드로 실행됩니다. 출력 NIfTI는 Docker 결과와 100% 동일합니다 (max diff=0.0000).

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

Docker Compose는 SynthSR(Step 30), SynthSeg Linux(Step 40), FastSurfer(Step 50)에서 사용합니다.

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
| `[ERR] conda env 'synthseg-metal' not found` | 환경 미구성 | `bash scripts/setup_tf_metal_env.sh` 실행 |
| `[ERR] run_native_test.py not found` | `synthseg_src/` 미설치 | `scripts/setup_tf_metal_env.sh` 재실행 |
| `[WARN] nibabel not found` | python3-nibabel not installed | `pip install nibabel` (optional but recommended) |
| FastSurfer OOM on Mac | 2D or thick-slice input | Use SynthSeg result instead; do not run FastSurfer |
| Slow SynthSR on Mac | amd64 emulation on ARM | Expected; use for single-case validation only |

---

## 라이선스 파일 준비 (FreeSurfer)

FreeSurfer 라이선스는 SynthSR(30단계) 및 FastSurfer(50단계)에서 필요합니다.

1. [https://surfer.nmr.mgh.harvard.edu/registration.html](https://surfer.nmr.mgh.harvard.edu/registration.html) 에서 무료 등록
2. 발급된 `license.txt`를 `FS_LICENSE_DIR`에 위치
3. `.env`의 `FS_LICENSE_DIR`과 `FS_LICENSE_FILE`을 파일 위치에 맞게 설정

---

## Project Structure

```
fastsurfer-docker/
├── easy-synthseg                 # TUI entry point (chmod +x, run with ./easy-synthseg)
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
│   ├── 40_synthseg_native.sh     # SynthSeg 기본 (Mac ARM64)
│   ├── 40_synthseg.sh            # SynthSeg Docker fallback (Linux)
│   ├── 50_fastsurfer.sh
│   ├── 90_pipeline.sh
│   ├── setup_tf_metal_env.sh     # Mac 네이티브 환경 구성 (1회)
│   └── tui.py                    # TUI 본체 (Python + Rich)
├── synthseg_src/
│   ├── run_native_test.py        # SynthSeg CLI wrapper (BatchNorm 5D 패치 포함)
│   └── SynthSeg/                 # SynthSeg 소스 + 가중치
└── data/                         # input/output data (not committed)
```

---

## License

이 프로젝트의 래퍼 코드(스크립트, TUI)는 **FreeSurfer Software License (v1.0)** 를 따릅니다 — 비상업적 연구 목적으로만 사용 가능합니다. 전문은 [LICENSE](LICENSE)를 참고하세요.

파이프라인이 호출하는 각 도구는 별도 라이선스를 따릅니다:

| Tool | License |
|------|---------|
| [FreeSurfer](https://surfer.nmr.mgh.harvard.edu) | [FreeSurfer Software License](https://surfer.nmr.mgh.harvard.edu/fswiki/FreeSurferSoftwareLicense) |
| [SynthSR](https://github.com/BBillot/SynthSR) | Apache-2.0 |
| [SynthSeg](https://github.com/BBillot/SynthSeg) | Apache-2.0 |
| [FastSurfer](https://github.com/Deep-MI/FastSurfer) | Apache-2.0 |

> **Note**: SynthSR 및 FastSurfer 실행에는 유효한 FreeSurfer 라이선스 파일(`license.txt`)이 필요합니다.
> 무료 등록: https://surfer.nmr.mgh.harvard.edu/registration.html
