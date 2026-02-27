#!/usr/bin/env bash
# scripts/_common.sh — 공통 환경 변수 로드, 경로 조립, 디렉토리 생성
# 모든 pipeline 스크립트에서 source하여 사용:
#   source "$(dirname "$0")/_common.sh"

# 프로젝트 루트 감지 (이 파일 기준)
_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$_COMMON_DIR")"

# .env 로드
if [[ ! -f "${PROJECT_ROOT}/.env" ]]; then
  echo "[ERR] .env not found at ${PROJECT_ROOT}/.env" >&2
  exit 1
fi
set -a
source "${PROJECT_ROOT}/.env"
set +a

# 필수 변수 검증
: "${DATA_ROOT:?missing DATA_ROOT in .env}"
: "${SID:?missing SID in .env}"
: "${FS_LICENSE_DIR:?missing FS_LICENSE_DIR in .env}"
: "${FS_LICENSE_FILE:?missing FS_LICENSE_FILE in .env}"

# 파생 경로 조립 (set -a 로 export하여 Docker Compose에 전달)
set -a
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
set +a

# 출력 디렉토리 생성
mkdir -p "${NIFTI_DIR}" "${SYNTHSR_DIR}" "${SYNTHSEG_DIR}" \
         "${FASTSURFER_DIR}" "${LOG_DIR}"

# Docker Compose OS 분기
# COMPOSE_OS 환경변수로 override 가능 (기본값: mac)
COMPOSE_OS="${COMPOSE_OS:-mac}"
COMPOSE_COMMON="${PROJECT_ROOT}/compose/docker-compose.common.yml"
if [[ "$COMPOSE_OS" == "linux" ]]; then
  COMPOSE_OVERRIDE="${PROJECT_ROOT}/compose/docker-compose.linux-gpu.yml"
else
  COMPOSE_OVERRIDE="${PROJECT_ROOT}/compose/docker-compose.mac.yml"
fi
COMPOSE_CMD="docker compose -f ${COMPOSE_COMMON} -f ${COMPOSE_OVERRIDE}"

# nibabel 헤더 필터 유틸 (30_synthsr.sh, 50_fastsurfer.sh에서 공용)
_have_nibabel() {
  python3 -c "import nibabel" >/dev/null 2>&1
}

_nifti_info_json() {
  # 출력: {"z": <int>, "zmm": <float>}
  python3 - <<'PY' "$1"
import json, sys
try:
  import nibabel as nib
  img = nib.load(sys.argv[1])
  shp = img.shape
  z = int(shp[2]) if len(shp) >= 3 else 1
  zooms = img.header.get_zooms()
  zmm = float(zooms[2]) if len(zooms) >= 3 else 999.0
  print(json.dumps({"z": z, "zmm": zmm}))
except Exception:
  print(json.dumps({"z": 999, "zmm": 1.0}))
PY
}

# return 0 = 위험(2D/두꺼운 슬라이스), return 1 = 안전
_is_risky_2d() {
  local f="$1"
  if ! _have_nibabel; then
    return 1  # nibabel 없으면 판단 불가 → 안전으로 처리
  fi
  local j z zmm
  j="$(_nifti_info_json "$f")"
  z="$(echo "$j" | python3 -c "import json,sys; print(json.load(sys.stdin)['z'])")"
  zmm="$(echo "$j" | python3 -c "import json,sys; print(json.load(sys.stdin)['zmm'])")"
  if (( z <= 30 )); then
    return 0
  fi
  python3 -c "import sys; sys.exit(0 if float('$zmm') >= 2.5 else 1)"
  return $?
}
