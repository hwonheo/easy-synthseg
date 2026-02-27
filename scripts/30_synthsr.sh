#!/usr/bin/env bash
# 30_synthsr.sh — SynthSR (mri_synthsr) 실행
# 입력: ${SELECTED_NII} 또는 ${LOG_DIR}/selected_input.txt
# 출력: ${SYNTHSR_DIR}/${SID}_synthsr.nii.gz
set -euo pipefail

source "$(dirname "$0")/_common.sh"

# --- 입력 파일 결정 ---
# 환경변수 SELECTED_NII가 있으면 우선 사용, 없으면 selected_input.txt에서 읽기
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

INPUT_BASENAME="$(basename "$SELECTED_NII")"
OUTPUT="${SYNTHSR_DIR}/${SID}_synthsr.nii.gz"

echo "[INFO] SynthSR"
echo "       Input : ${SELECTED_NII}"
echo "       Output: ${OUTPUT}"

# --- 캐시 확인 ---
if [[ -f "$OUTPUT" && "${FORCE:-0}" != "1" ]]; then
  echo "[SKIP] SynthSR output already exists."
  echo "       (set FORCE=1 to overwrite)"
  exit 0
fi

# --- CPU 플래그 결정 ---
# Mac(amd64 에뮬레이션)은 GPU 없음 → --cpu 필수
# Linux GPU 서버는 --cpu 생략
if [[ "${COMPOSE_OS}" == "linux" ]]; then
  CPU_FLAG=""
else
  CPU_FLAG="--cpu"
fi

# --- Docker 실행 ---
echo "[RUN ] mri_synthsr (${COMPOSE_OS} mode)"
${COMPOSE_CMD} run --rm freesurfer \
  mri_synthsr \
  --i "/input/${INPUT_BASENAME}" \
  --o "/output/${SID}_synthsr.nii.gz" \
  ${CPU_FLAG}

echo "[DONE] SynthSR complete: ${OUTPUT}"
