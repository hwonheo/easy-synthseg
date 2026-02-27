# Easy SynthSR (TUI)

macOS (Apple Silicon) 및 Linux (GPU/HPC)를 위한 뇌 MRI 분할 파이프라인.

**SynthSR → SynthSeg** 를 기본 경로로 실행하며, 확인된 3D T1 영상에 한해 **FastSurfer** 를 선택적으로 실행할 수 있습니다.

**macOS (ARM64)**: SynthSeg는 네이티브 Python (`synthseg-metal` conda 환경)으로 직접 실행.
**Linux (GPU)**: SynthSeg는 Docker 컨테이너로 실행.

> English documentation: [README.md](README.md)

---

## 왜 이 레포를 만들게 되었나

SynthSR 하나 돌려보려고 했을 뿐이었다.

FreeSurfer 공식 문서를 열었더니 설치 가이드가 나왔다. 그냥 따라 하면 되겠거니 했는데, macOS ARM64에서 바이너리가 동작하지 않았다. Docker로 우회하면 되겠다고 생각했다. x86 에뮬레이션 위에서 돌아가는 SynthSR은 느렸다. 어차피 Docker 쓰는 김에 SynthSeg도 컨테이너로 묶었다. 그런데 Apple Silicon에서 GPU를 못 쓴다는 게 걸렸다. tensorflow-metal을 써서 네이티브로 돌려보기로 했다. conda 환경을 새로 구성했다. BatchNorm 레이어가 Metal을 지원하지 않아 CPU로 폴백됐다. 그래도 Docker 에뮬레이션보다 1.36배 빨랐다. SynthSeg가 됐으니 FastSurfer도 연결해보자는 생각이 들었다.

스크립트가 다섯 개가 됐다. 스크립트가 다섯 개면 실행 순서를 까먹는다. 그래서 파이프라인 스크립트를 만들었다. 그리고 TUI를 만들었다.

**SynthSR 하나 때문에 이렇게 됐다.**

---

## 파이프라인 개요

```
DICOM → NIfTI → [select] → SynthSR → SynthSeg → (FastSurfer)
  [10]    [10]     [20]       [30]       [40]         [50]
```

| 단계 | 스크립트 | 도구 | 비고 |
|------|----------|------|------|
| DICOM → NIfTI | `10_dicom2nifti.sh` | dcm2niix | 캐시; NIfTI 존재 시 건너뜀 |
| NIfTI 선택 | `20_select_nifti.sh` | nibabel | 블랙리스트 + 2D/두꺼운 슬라이스 자동 제외 |
| SynthSR | `30_synthsr.sh` | freesurfer/freesurfer | 초해상도; Mac에서 `--cpu` |
| SynthSeg (Mac) | `40_synthseg_native.sh` | tensorflow-metal + SynthSeg | ARM64 네이티브, Docker 대비 1.36× 빠름 |
| SynthSeg (Linux) | `40_synthseg.sh` | pwesp/synthseg (Docker) | GPU 지원 |
| FastSurfer | `50_fastsurfer.sh` | deepmi/fastsurfer | 선택; 실행 전 헤더 안전 확인 |

`90_pipeline.sh`가 `COMPOSE_OS` 값에 따라 Step 40을 자동 분기합니다.

---

## 요구사항

### 공통

| 도구 | Mac | Linux |
|------|-----|-------|
| dcm2niix | `brew install dcm2niix` | system package or container |
| python3 + nibabel | `pip install nibabel` | 권장 |
| FreeSurfer 라이선스 | `license.txt` | 동일 |

### macOS (ARM64) — SynthSeg 네이티브 실행

| 항목 | 비고 |
|------|------|
| miniforge (arm64) | [miniforge 설치](https://github.com/conda-forge/miniforge) |
| conda env `synthseg-metal` | `bash scripts/setup_tf_metal_env.sh` 로 자동 구성 |

```bash
# 처음 한 번만 실행
bash scripts/setup_tf_metal_env.sh
```

### Linux — Docker

| 항목 | 비고 |
|------|------|
| Docker Desktop / Engine | 필수 |

---

## 빠른 시작

### 1. `.env` 설정

```bash
cp .env.example .env
```

`.env` 편집:

```bash
DATA_ROOT=/path/to/data   # 데이터 루트
SID=subjectX              # 피험자 ID
FS_LICENSE_DIR=/path/to/freesurfer/license
FS_LICENSE_FILE=license.txt
THREADS=4
```

### 2. DICOM 파일 배치

```
data/
└── dicom/
    └── subjectX/    ← DICOM 파일을 여기에
```

### 3. (Mac only) 네이티브 SynthSeg 환경 구성

```bash
bash scripts/setup_tf_metal_env.sh
```

### 4. 실행

```bash
# 인터랙티브 TUI (권장)
./easy-synthseg

# 직접 실행 — macOS ARM64
./scripts/90_pipeline.sh

# 직접 실행 — Linux GPU
COMPOSE_OS=linux ./scripts/90_pipeline.sh
```

---

## 출력 구조

```
data/
├── dicom/subjectX/                    # 원본 DICOM (입력)
├── nifti/subjectX/                    # dcm2niix 출력
├── derivatives/subjectX/
│   ├── synthsr/
│   │   └── subjectX_synthsr.nii.gz    # SynthSR 결과
│   ├── synthseg/
│   │   ├── subjectX_synthseg.nii.gz   # SynthSeg 분할
│   │   └── subjectX_synthseg_vols.csv # 영역별 부피
│   └── fastsurfer/                    # FastSurfer 결과 (실행 시)
└── logs/subjectX/
    └── selected_input.txt             # 재현성 기록
```

---

## 개별 스텝 실행

모든 스크립트는 독립 실행 가능합니다. `.env`는 자동으로 로드됩니다.

```bash
./scripts/00_env_check.sh           # 의존성 확인
./scripts/10_dicom2nifti.sh         # DICOM → NIfTI
./scripts/20_select_nifti.sh        # 입력 파일 선택
./scripts/30_synthsr.sh             # SynthSR 실행
./scripts/40_synthseg_native.sh     # SynthSeg (Mac ARM64, 기본값)
./scripts/40_synthseg.sh            # SynthSeg (Docker fallback)
./scripts/50_fastsurfer.sh          # FastSurfer (선택)
```

### 캐시 / 강제 재실행

```bash
FORCE=1 ./scripts/30_synthsr.sh
FORCE=1 ./scripts/40_synthseg_native.sh
FORCE_CONVERT=1 ./scripts/10_dicom2nifti.sh
```

---

## Mac vs Linux

| `COMPOSE_OS` | Step 40 | 플랫폼 | GPU |
|---|---|---|---|
| `mac` (기본값) | `40_synthseg_native.sh` | ARM64 네이티브 | Metal (CPU fallback) |
| `linux` | `40_synthseg.sh` (Docker) | native | NVIDIA GPU |

### macOS SynthSeg 성능

| 방식 | 평균 처리 시간 | 비고 |
|------|:-------------:|------|
| Docker x86 에뮬레이션 (이전) | 398.7s ± 4.9s | Rosetta 에뮬레이션 |
| Native ARM64 (현재 기본값) | 292.3s ± 4.9s | **1.36× 빠름** |

> tensorflow-metal이 Metal GPU를 인식하나, SynthSeg의 3D BatchNorm이 Metal FusedBN 미지원으로
> CPU 모드로 실행됩니다. 출력 NIfTI는 Docker 결과와 100% 동일합니다 (max diff = 0.0000).

---

## NIfTI 후보 선택

`20_select_nifti.sh`는 두 단계로 후보를 필터링합니다:

**1. 블랙리스트** (항상 적용):

```
dwi, dti, adc, trace, swi, angio, tof, mra, spine,
localizer, survey, t2, flair, fse, gre, ...
```

**2. 헤더 안전 확인** (nibabel 필요):

- 슬라이스 수 ≤ 30 또는 복셀 z-크기 ≥ 2.5 mm → FastSurfer 후보에서 제외
- 제외된 파일은 SynthSeg 전용 권장과 함께 표시됨

선택 결과는 `data/logs/{SID}/selected_input.txt`에 기록됩니다.

---

## Compose 구조

Docker Compose는 SynthSR(Step 30), SynthSeg Linux(Step 40), FastSurfer(Step 50)에서 사용합니다.

```
compose/
├── docker-compose.common.yml    # 서비스 정의 (freesurfer, synthseg, fastsurfer)
├── docker-compose.mac.yml       # platform: linux/amd64, user: 0:0
└── docker-compose.linux-gpu.yml # GPU 예약
```

---

## 문제 해결

| 증상 | 원인 | 해결 |
|------|------|------|
| `[ERR] DICOM directory not found` | `data/dicom/{SID}/` 없음 | 디렉토리 생성 후 DICOM 파일 배치 |
| `[ERR] SynthSR output not found` | Step 30 미실행 | `30_synthsr.sh` 먼저 실행 |
| `[ERR] FS license not found` | 잘못된 `FS_LICENSE_DIR` 또는 `FS_LICENSE_FILE` | `.env` 및 파일 경로 확인 |
| `[ERR] conda env 'synthseg-metal' not found` | 환경 미구성 | `bash scripts/setup_tf_metal_env.sh` 실행 |
| `[ERR] run_native_test.py not found` | `synthseg_src/` 미설치 | `scripts/setup_tf_metal_env.sh` 재실행 |
| `[WARN] nibabel not found` | python3-nibabel 미설치 | `pip install nibabel` (선택이지만 권장) |
| FastSurfer OOM on Mac | 2D 또는 두꺼운 슬라이스 입력 | SynthSeg 결과만 사용; FastSurfer 생략 |
| Mac에서 SynthSR 느림 | ARM에서 amd64 에뮬레이션 | 단일 케이스 검증 시에만 사용 |

---

## FreeSurfer 라이선스 준비

FreeSurfer 라이선스는 SynthSR(30단계) 및 FastSurfer(50단계)에서 필요합니다.

1. https://surfer.nmr.mgh.harvard.edu/registration.html 에서 무료 등록
2. 발급된 `license.txt`를 `FS_LICENSE_DIR`에 위치
3. `.env`의 `FS_LICENSE_DIR`과 `FS_LICENSE_FILE`을 파일 위치에 맞게 설정

---

## 프로젝트 구조

```
easy-synthseg/
├── easy-synthseg                 # TUI 진입점 (./easy-synthseg 으로 실행)
├── .env                          # 로컬 설정 (커밋 안 됨)
├── .env.example                  # 템플릿
├── compose/
│   ├── docker-compose.common.yml
│   ├── docker-compose.mac.yml
│   └── docker-compose.linux-gpu.yml
├── scripts/
│   ├── _common.sh                # 공통 환경 로더 + nibabel 유틸
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
│   ├── run_native_test.py        # SynthSeg CLI 래퍼 (BatchNorm 5D 패치 포함)
│   └── SynthSeg/                 # SynthSeg 소스 + 가중치 (커밋 안 됨)
└── data/                         # 입출력 데이터 (커밋 안 됨)
```

---

## 라이선스

이 프로젝트의 래퍼 코드(스크립트, TUI)는 **FreeSurfer Software License (v1.0)** 를 따릅니다 — 비상업적 연구 목적으로만 사용 가능합니다. 전문은 [LICENSE](LICENSE)를 참고하세요.

| 도구 | 라이선스 |
|------|---------|
| [FreeSurfer](https://surfer.nmr.mgh.harvard.edu) | [FreeSurfer Software License](https://surfer.nmr.mgh.harvard.edu/fswiki/FreeSurferSoftwareLicense) |
| [SynthSR](https://github.com/BBillot/SynthSR) | Apache-2.0 |
| [SynthSeg](https://github.com/BBillot/SynthSeg) | Apache-2.0 |
| [FastSurfer](https://github.com/Deep-MI/FastSurfer) | Apache-2.0 |
