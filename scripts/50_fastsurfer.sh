#!/usr/bin/env bash
# 50_fastsurfer.sh — FastSurfer 실행 (조건부: 3D T1 + 헤더 안전 시만)
# 입력: ${SELECTED_NII} (원본 NIfTI, SynthSR 아님)
# 출력: ${FASTSURFER_DIR}/
set -euo pipefail

source "$(dirname "$0")/_common.sh"

# --- 입력 파일 결정 ---
if [[ -z "${SELECTED_NII:-}" ]]; then
  SELECTED_LOG="${LOG_DIR}/selected_input.txt"
  if [[ ! -f "$SELECTED_LOG" ]]; then
    echo "[ERR] SELECTED_NII not set and ${SELECTED_LOG} not found." >&2
    echo "      Run 20_select_nifti.sh first." >&2
    exit 1
  fi
  SELECTED_NII="$(grep '^SELECTED=' "$SELECTED_LOG" | cut -d= -f2)"
fi

if [[ ! -f "$SELECTED_NII" ]]; then
  echo "[ERR] Input NIfTI not found: ${SELECTED_NII}" >&2
  exit 1
fi

T1_NAME="$(basename "$SELECTED_NII")"

echo "[INFO] FastSurfer"
echo "       Input : ${SELECTED_NII}"
echo "       Output: ${FASTSURFER_DIR}"

# --- 헤더 안전성 검사 ---
if _have_nibabel; then
  if _is_risky_2d "$SELECTED_NII"; then
    echo "[WARN] FastSurfer 안전 기준 미달 (z≤30 또는 zmm≥2.5mm)."
    echo "       이 파일은 FastSurfer OOM 위험이 있습니다."
    echo "       SynthSeg 결과를 사용하는 것을 권장합니다."
    read -rp "       그래도 계속 실행하시겠습니까? [y/N]: " yn
    if [[ ! "$yn" =~ ^[Yy]$ ]]; then
      echo "[SKIP] FastSurfer skipped by user."
      exit 0
    fi
  fi
fi

# --- Docker 실행 ---
echo "[RUN ] FastSurfer (${COMPOSE_OS} mode)"
export T1_REL="${T1_NAME}"
export FASTSURFER_IN="${NIFTI_DIR}"
export FASTSURFER_OUT_DIR="${FASTSURFER_DIR}"

${COMPOSE_CMD} run --rm \
  -e T1_REL="${T1_REL}" \
  fastsurfer

echo "[DONE] FastSurfer complete: ${FASTSURFER_DIR}/${SID}/"
