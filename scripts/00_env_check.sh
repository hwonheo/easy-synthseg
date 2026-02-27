#!/usr/bin/env bash
# 00_env_check.sh — 의존성 사전 체크
# 파이프라인 실행 전 필수 조건 검증
set -euo pipefail

source "$(dirname "$0")/_common.sh"

echo "[INFO] Environment check (COMPOSE_OS=${COMPOSE_OS})"
echo ""

ERRORS=0

check_ok()   { printf "  [OK  ] %s\n" "$1"; }
check_warn() { printf "  [WARN] %s\n" "$1"; }
check_err()  { printf "  [ERR ] %s\n" "$1"; ERRORS=$(( ERRORS + 1 )); }

# --- dcm2niix ---
if command -v dcm2niix >/dev/null 2>&1; then
  check_ok "dcm2niix: $(dcm2niix --version 2>&1 | head -1)"
else
  check_err "dcm2niix not found. Install: brew install dcm2niix"
fi

# --- Docker ---
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  check_ok "Docker: $(docker --version)"
else
  check_err "Docker not running or not installed."
fi

# --- python3 + nibabel ---
if command -v python3 >/dev/null 2>&1; then
  if python3 -c "import nibabel" >/dev/null 2>&1; then
    check_ok "python3 nibabel: $(python3 -c "import nibabel; print(nibabel.__version__)")"
  else
    check_warn "nibabel not installed → header-based 2D filtering disabled."
    echo "           Install: python3 -m pip install nibabel"
  fi
else
  check_warn "python3 not found → nibabel filtering disabled."
fi

# --- FreeSurfer 라이선스 ---
LICENSE_PATH="${FS_LICENSE_DIR}/${FS_LICENSE_FILE}"
if [[ -f "$LICENSE_PATH" ]]; then
  check_ok "FS license: ${LICENSE_PATH}"
else
  check_err "FS license not found: ${LICENSE_PATH}"
fi

# --- DATA_ROOT 존재 ---
if [[ -d "$DATA_ROOT" ]]; then
  check_ok "DATA_ROOT: ${DATA_ROOT}"
else
  check_warn "DATA_ROOT does not exist, will be created: ${DATA_ROOT}"
  mkdir -p "${DATA_ROOT}"
fi

# --- DICOM 디렉토리 ---
# DICOM 파일 수 계산: .dcm/.IMA 확장자 또는 확장자 없는 파일(PACS export) 포함
_count_dicom() {
  local dir="$1"
  # 확장자 있는 DICOM
  local n_ext
  n_ext="$(find "$dir" -type f \( -name "*.dcm" -o -name "*.IMA" \) 2>/dev/null | wc -l | tr -d ' ')"
  # 확장자 없는 파일 (숫자/문자 파일명, .DS_Store 등 숨김파일 제외)
  local n_noext
  n_noext="$(find "$dir" -type f ! -name "*.*" ! -name ".*" 2>/dev/null | wc -l | tr -d ' ')"
  echo $(( n_ext + n_noext ))
}

if [[ -d "$DICOM_DIR" ]]; then
  DICOM_COUNT="$(_count_dicom "$DICOM_DIR")"
  SUBDIR_COUNT="$(find "$DICOM_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  if (( DICOM_COUNT > 0 )); then
    check_ok "DICOM dir: ${DICOM_DIR} (${DICOM_COUNT} files, ${SUBDIR_COUNT} subdir(s))"
  else
    check_warn "DICOM dir exists but no DICOM files found: ${DICOM_DIR}"
    echo "           Subdirectories: ${SUBDIR_COUNT}"
    echo "           Place DICOM files at ${DICOM_DIR}"
  fi
  # 하위 폴더/파일 목록 출력 (최대 1단계)
  if (( SUBDIR_COUNT > 0 )); then
    echo "           Subdirs:"
    find "$DICOM_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
      | sort | while read -r d; do
          f_count="$(_count_dicom "$d")"
          printf "             %-40s (%s files)\n" "$(basename "$d")" "$f_count"
        done
  fi
  # DICOM_DIR 바로 아래 flat 파일
  FLAT_EXT="$(find "$DICOM_DIR" -mindepth 1 -maxdepth 1 -type f \( -name "*.dcm" -o -name "*.IMA" \) 2>/dev/null | wc -l | tr -d ' ')"
  FLAT_NOEXT="$(find "$DICOM_DIR" -mindepth 1 -maxdepth 1 -type f ! -name "*.*" ! -name ".*" 2>/dev/null | wc -l | tr -d ' ')"
  FLAT_COUNT=$(( FLAT_EXT + FLAT_NOEXT ))
  if (( FLAT_COUNT > 0 )); then
    echo "           Files (flat): ${FLAT_COUNT}"
  fi
else
  check_warn "DICOM dir not found: ${DICOM_DIR}"
  echo "           Place DICOM files at ${DICOM_DIR}"
fi

echo ""
if (( ERRORS > 0 )); then
  echo "[FAIL] ${ERRORS} error(s) found. Fix above issues before running the pipeline."
  exit 1
else
  echo "[PASS] All required dependencies satisfied."
fi
