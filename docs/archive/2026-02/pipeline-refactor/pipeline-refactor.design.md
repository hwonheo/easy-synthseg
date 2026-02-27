# [Design] pipeline-refactor

> FastSurfer Hybrid Mac/Linux 파이프라인 상세 설계

**참조 Plan**: `docs/01-plan/features/pipeline-refactor.plan.md`
**작성일**: 2026-02-26
**상태**: Design

---

## 1. 디렉토리 구조 설계

### 1-1. 프로젝트 루트

```
fastsurfer-docker/
├── .env                           # DATA_ROOT 기반 환경변수 (재작성)
├── .env.example                   # 템플릿 (커밋 대상)
├── compose/
│   ├── docker-compose.common.yml  # 서비스 정의 (synthseg, freesurfer, fastsurfer)
│   ├── docker-compose.mac.yml     # Mac: platform=linux/amd64, user=0:0
│   └── docker-compose.linux-gpu.yml  # Linux: GPU 예약
├── scripts/
│   ├── 00_env_check.sh            # 의존성 체크 (dcm2niix, docker, nibabel)
│   ├── 10_dicom2nifti.sh          # DICOM → NIfTI 변환 (캐시)
│   ├── 20_select_nifti.sh         # 후보 선택 + 기록
│   ├── 30_synthsr.sh              # SynthSR 실행 [신규]
│   ├── 40_synthseg.sh             # SynthSeg 실행 (SynthSR 출력 사용)
│   ├── 50_fastsurfer.sh           # FastSurfer 실행 (조건부)
│   └── 90_pipeline.sh             # 전체 오케스트레이터 [신규]
└── data/
    ├── dicom/
    │   └── {SID}/                 # 원본 DICOM
    ├── nifti/
    │   └── {SID}/                 # dcm2niix 결과
    ├── derivatives/
    │   └── {SID}/
    │       ├── synthsr/           # 30_synthsr.sh 출력
    │       ├── synthseg/          # 40_synthseg.sh 출력
    │       └── fastsurfer/        # 50_fastsurfer.sh 출력
    └── logs/
        └── {SID}/
            └── selected_input.txt # 20_select_nifti.sh 기록
```

---

## 2. .env 설계 (R-01)

### 2-1. 신규 .env 스키마

```bash
# ── 루트 ──────────────────────────────────────────
DATA_ROOT=/Users/hwon/Documents/Git/fastsurfer-docker/data

# ── 케이스 선택 ───────────────────────────────────
SID=subjectX

# ── 파생 경로 (스크립트 내부에서 조립, .env에서는 선언만) ──
# DICOM_ROOT=${DATA_ROOT}/dicom       # → ${DICOM_ROOT}/${SID}
# NIFTI_ROOT=${DATA_ROOT}/nifti       # → ${NIFTI_ROOT}/${SID}
# DERIV_ROOT=${DATA_ROOT}/derivatives # → ${DERIV_ROOT}/${SID}/synthsr|synthseg|fastsurfer
# LOG_ROOT=${DATA_ROOT}/logs          # → ${LOG_ROOT}/${SID}

# ── 라이선스 ──────────────────────────────────────
FS_LICENSE_DIR=/Users/hwon/.local/bin
FS_LICENSE_FILE=license.txt

# ── 실행 옵션 ─────────────────────────────────────
THREADS=4
FORCE_CONVERT=0   # 1이면 dcm2niix 재실행
FORCE=0           # 1이면 synthsr/synthseg/fastsurfer 결과 overwrite
```

### 2-2. 공통 env 로드 헬퍼 (scripts/_common.sh)

각 스크립트에서 source하는 공통 헬퍼:

```bash
#!/usr/bin/env bash
# scripts/_common.sh — 공통 환경 변수 조립 및 디렉토리 생성

# .env 로드 (호출 스크립트 위치 기준)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
set -a; source "${PROJECT_ROOT}/.env"; set +a

# 필수 변수 검증
: "${DATA_ROOT:?missing DATA_ROOT}"
: "${SID:?missing SID}"
: "${FS_LICENSE_DIR:?missing FS_LICENSE_DIR}"
: "${FS_LICENSE_FILE:?missing FS_LICENSE_FILE}"

# 파생 경로 조립
DICOM_ROOT="${DATA_ROOT}/dicom"
NIFTI_ROOT="${DATA_ROOT}/nifti"
DERIV_ROOT="${DATA_ROOT}/derivatives"
LOG_ROOT="${DATA_ROOT}/logs"

DICOM_DIR="${DICOM_ROOT}/${SID}"
NIFTI_DIR="${NIFTI_ROOT}/${SID}"
SYNTHSR_DIR="${DERIV_ROOT}/${SID}/synthsr"
SYNTHSEG_DIR="${DERIV_ROOT}/${SID}/synthseg"
FASTSURFER_DIR="${DERIV_ROOT}/${SID}/fastsurfer"
LOG_DIR="${LOG_ROOT}/${SID}"

# 디렉토리 생성
mkdir -p "${NIFTI_DIR}" "${SYNTHSR_DIR}" "${SYNTHSEG_DIR}" \
         "${FASTSURFER_DIR}" "${LOG_DIR}"

# Compose OS별 분기
COMPOSE_OS="${COMPOSE_OS:-mac}"   # 환경변수로 override 가능
COMPOSE_BASE="-f ${PROJECT_ROOT}/compose/docker-compose.common.yml"
if [[ "$COMPOSE_OS" == "linux" ]]; then
  COMPOSE_OVERRIDE="-f ${PROJECT_ROOT}/compose/docker-compose.linux-gpu.yml"
else
  COMPOSE_OVERRIDE="-f ${PROJECT_ROOT}/compose/docker-compose.mac.yml"
fi
COMPOSE_CMD="docker compose ${COMPOSE_BASE} ${COMPOSE_OVERRIDE}"
```

---

## 3. Docker Compose 설계 (R-06)

### 3-1. compose/docker-compose.common.yml

서비스 정의만 포함 (플랫폼/GPU 설정 없음):

```yaml
services:
  freesurfer:
    image: freesurfer/freesurfer:7.4.1
    container_name: freesurfer_synthsr
    volumes:
      - ${NIFTI_DIR}:/input:ro
      - ${SYNTHSR_DIR}:/output
      - ${FS_LICENSE_DIR}:/fs_license:ro
    environment:
      - FS_LICENSE=/fs_license/${FS_LICENSE_FILE}
    entrypoint: []   # command로 덮어씀

  synthseg:
    image: pwesp/synthseg:py38
    container_name: synthseg
    volumes:
      - ${SYNTHSR_DIR}:/synthsr:ro
      - ${SYNTHSEG_DIR}:/output

  fastsurfer:
    image: deepmi/fastsurfer:latest
    container_name: fastsurfer
    volumes:
      - ${NIFTI_DIR}:/data:ro
      - ${FASTSURFER_DIR}:/output
      - ${FS_LICENSE_DIR}:/fs_license:ro
    command:
      - --allow_root
      - --fs_license
      - /fs_license/${FS_LICENSE_FILE}
      - --t1
      - /data/${T1_REL}
      - --sid
      - ${SID}
      - --sd
      - /output
      - --3T
      - --threads
      - "${THREADS:-4}"
```

### 3-2. compose/docker-compose.mac.yml

```yaml
services:
  freesurfer:
    platform: linux/amd64
    user: "0:0"

  synthseg:
    platform: linux/amd64

  fastsurfer:
    platform: linux/amd64
    user: "0:0"
```

### 3-3. compose/docker-compose.linux-gpu.yml

```yaml
services:
  fastsurfer:
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
```

---

## 4. 스크립트 상세 설계 (R-02, R-03, R-05)

### 4-1. 00_env_check.sh

**목적**: 의존성 사전 확인, 실행 실패 방지

**검사 항목**:
- `dcm2niix` 명령어 존재 여부
- `docker` 실행 가능 여부
- `python3 -c "import nibabel"` nibabel 설치 여부
- `${FS_LICENSE_DIR}/${FS_LICENSE_FILE}` 파일 존재 여부
- `DATA_ROOT` 디렉토리 존재 여부

**출력**: 각 항목 `[OK]` / `[WARN]` / `[ERR]` 표시, ERR 있으면 exit 1

---

### 4-2. 10_dicom2nifti.sh

**입력**: `${DICOM_DIR}` (DICOM 파일)
**출력**: `${NIFTI_DIR}/*.nii.gz`

**로직**:
```
if [ NIfTI 파일 이미 존재 ] && [ FORCE_CONVERT != 1 ]:
    echo "[SKIP] NIfTI already exists"
else:
    dcm2niix -f %d_%s -z y -o ${NIFTI_DIR} ${DICOM_DIR}
```

---

### 4-3. 20_select_nifti.sh

**입력**: `${NIFTI_DIR}/*.nii*`
**출력**: `${LOG_DIR}/selected_input.txt` (선택된 파일 절대경로)
**환경변수 export**: `SELECTED_NII` (이후 스크립트에서 사용)

**로직**:
1. `BLACKLIST` 패턴으로 1차 제외
2. nibabel로 헤더 검사 → z≤30 또는 zmm≥2.5 → `[EXCLUDED]` 목록
3. 대화형 선택 메뉴 출력
4. 선택 결과를 `${LOG_DIR}/selected_input.txt`에 기록

**selected_input.txt 형식**:
```
# SID: subjectX
# 선택일시: 2026-02-26T12:00:00
# 목적: synthsr+synthseg (fastsurfer 제외: 헤더 위험)
SELECTED=/path/to/nifti/subjectX/T1_mprage_0001.nii.gz
```

---

### 4-4. 30_synthsr.sh (신규, R-02)

**입력**: `${SELECTED_NII}` (20_select_nifti.sh 결과) 또는 `${LOG_DIR}/selected_input.txt` 에서 읽기
**출력**: `${SYNTHSR_DIR}/${SID}_synthsr.nii.gz`
**Docker 서비스**: `freesurfer` (mri_synthsr 실행)

**캐시 로직**:
```
OUTPUT=${SYNTHSR_DIR}/${SID}_synthsr.nii.gz
if [ -f $OUTPUT ] && [ FORCE != 1 ]:
    echo "[SKIP] SynthSR output exists"
    exit 0
```

**Docker 실행 설계**:
```bash
${COMPOSE_CMD} run --rm freesurfer \
  mri_synthsr \
  --i /input/$(basename ${SELECTED_NII}) \
  --o /output/${SID}_synthsr.nii.gz \
  --cpu   # Mac에서는 CPU 모드 (GPU 없음)
```

**주의사항**:
- Mac: `--cpu` 플래그 필요 (GPU 없음)
- Linux: GPU 사용 시 `--cpu` 제거

---

### 4-5. 40_synthseg.sh (수정, R-03)

**입력**: `${SYNTHSR_DIR}/${SID}_synthsr.nii.gz` ← **SynthSR 출력 고정**
**출력**: `${SYNTHSEG_DIR}/${SID}_synthseg.nii.gz`
**Docker 서비스**: `synthseg`

**캐시 로직**:
```
INPUT=${SYNTHSR_DIR}/${SID}_synthsr.nii.gz
OUTPUT=${SYNTHSEG_DIR}/${SID}_synthseg.nii.gz

if [ ! -f $INPUT ]:
    echo "[ERR] SynthSR output not found. Run 30_synthsr.sh first."
    exit 1

if [ -f $OUTPUT ] && [ FORCE != 1 ]:
    echo "[SKIP] SynthSeg output exists"
    exit 0
```

**Docker 실행 설계**:
```bash
${COMPOSE_CMD} run --rm synthseg \
  python /workspace/SynthSeg/scripts/commands/SynthSeg_predict.py \
  --i /synthsr/${SID}_synthsr.nii.gz \
  --o /output/${SID}_synthseg.nii.gz
```

---

### 4-6. 50_fastsurfer.sh (분리, R-05)

**입력**: `${SELECTED_NII}` (원본 NIfTI, SynthSR 아님)
**출력**: `${FASTSURFER_DIR}/`
**Docker 서비스**: `fastsurfer`

**사전 조건 검사**:
- nibabel 헤더 검사: z>30 AND zmm<2.5 → 안전한 경우만 실행
- 위험 시: `[WARN] FastSurfer 안전 기준 미달. SynthSeg 결과 사용 권장.` + exit 0 (에러 아님)

**Docker 실행**: 기존 docker-compose.yml 로직 유지

---

### 4-7. 90_pipeline.sh (신규, R-07)

**전체 파이프라인 오케스트레이터**

```bash
#!/usr/bin/env bash
# 90_pipeline.sh

source scripts/_common.sh

# 단계별 실행 (실패 시 중단)
bash scripts/00_env_check.sh   || exit 1
bash scripts/10_dicom2nifti.sh || exit 1
bash scripts/20_select_nifti.sh || exit 1

# SELECTED_NII 읽기 (20_select에서 기록)
SELECTED_NII=$(grep '^SELECTED=' "${LOG_DIR}/selected_input.txt" | cut -d= -f2)
export SELECTED_NII

bash scripts/30_synthsr.sh     || exit 1
bash scripts/40_synthseg.sh    || exit 1

# FastSurfer는 조건부 (사용자 확인)
read -rp "Run FastSurfer (optional, 3D T1 only)? [y/N]: " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
  bash scripts/50_fastsurfer.sh
fi

echo ""
echo "=== Pipeline Complete ==="
echo "  SynthSR:  ${SYNTHSR_DIR}/${SID}_synthsr.nii.gz"
echo "  SynthSeg: ${SYNTHSEG_DIR}/${SID}_synthseg.nii.gz"
```

---

## 5. 데이터 흐름 다이어그램

```
data/dicom/{SID}/
    │
    │ [10_dicom2nifti.sh] dcm2niix
    ▼
data/nifti/{SID}/*.nii.gz
    │
    │ [20_select_nifti.sh] blacklist + 헤더 필터 + 대화형 선택
    ▼
selected_input.txt (재현성 기록)
    │ SELECTED_NII
    │
    ├──────────────────────────────────┐
    │ [30_synthsr.sh]                  │ [50_fastsurfer.sh] (조건부)
    │ freesurfer:mri_synthsr --cpu     │ deepmi/fastsurfer
    ▼                                  ▼
data/derivatives/{SID}/synthsr/       data/derivatives/{SID}/fastsurfer/
{SID}_synthsr.nii.gz
    │
    │ [40_synthseg.sh]
    │ pwesp/synthseg (SynthSR 출력 입력)
    ▼
data/derivatives/{SID}/synthseg/
{SID}_synthseg.nii.gz
```

---

## 6. 파일별 변경/신규 매핑

| 파일 | 상태 | 비고 |
|------|------|------|
| `.env` | 수정 | DATA_ROOT 기반으로 전면 재작성 |
| `.env.example` | 수정 | .env 스키마에 맞게 갱신 |
| `scripts/_common.sh` | 신규 | 공통 env 로드 + 경로 조립 |
| `scripts/00_env_check.sh` | 신규 | 의존성 사전 체크 |
| `scripts/10_dicom2nifti.sh` | 신규 | run_fastsurfer.sh 1단계 분리 |
| `scripts/20_select_nifti.sh` | 신규 | run_fastsurfer.sh 2단계 분리 + 기록 |
| `scripts/30_synthsr.sh` | 신규 | SynthSR 단계 (핵심 누락 보완) |
| `scripts/40_synthseg.sh` | 신규 | SynthSR 출력 입력으로 |
| `scripts/50_fastsurfer.sh` | 신규 | run_fastsurfer.sh 4단계 분리 |
| `scripts/90_pipeline.sh` | 신규 | 전체 오케스트레이터 |
| `compose/docker-compose.common.yml` | 신규 | 3서비스 통합 |
| `compose/docker-compose.mac.yml` | 신규 (이동) | 루트에서 이동 |
| `compose/docker-compose.linux-gpu.yml` | 신규 (이동) | 루트에서 이동 |
| `run_fastsurfer.sh` | 삭제 예정 | scripts/로 분리 후 제거 |
| `run_synthseg.sh` | 삭제 예정 | scripts/40_synthseg.sh로 대체 |
| `docker-compose.yml` | 삭제 예정 | compose/로 이동 후 제거 |
| `docker-compose.mac.yml` | 삭제 예정 | compose/로 이동 |
| `docker-compose.linux-gpu.yml` | 삭제 예정 | compose/로 이동 |
| `docker-compose.synthseg.mac.yml` | 삭제 예정 | common.yml로 통합 |

---

## 7. 완료 검증 기준

| 검증 항목 | 검증 방법 |
|-----------|-----------|
| SynthSeg 입력이 SynthSR 출력인지 | `40_synthseg.sh` 내 INPUT 경로 확인 |
| derivatives/ 하위 결과 저장 | `ls data/derivatives/$SID/synthsr/` |
| selected_input.txt 생성 | `cat data/logs/$SID/selected_input.txt` |
| Mac Compose 분기 | `COMPOSE_OS=mac ./scripts/90_pipeline.sh` |
| Linux Compose 분기 | `COMPOSE_OS=linux ./scripts/90_pipeline.sh` |
| 캐시 동작 | FORCE=0으로 재실행 시 [SKIP] 출력 |
