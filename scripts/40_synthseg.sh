#!/usr/bin/env bash
# 40_synthseg.sh — SynthSeg 실행
# 입력: ${SYNTHSR_DIR}/${SID}_synthsr.nii.gz  (SynthSR 출력 고정)
# 출력: ${SYNTHSEG_DIR}/${SID}_synthseg.nii.gz
set -euo pipefail

source "$(dirname "$0")/_common.sh"

INPUT="${SYNTHSR_DIR}/${SID}_synthsr.nii.gz"
OUTPUT="${SYNTHSEG_DIR}/${SID}_synthseg.nii.gz"
OUTPUT_VOL="${SYNTHSEG_DIR}/${SID}_synthseg_vols.csv"

echo "[INFO] SynthSeg"
echo "       Input : ${INPUT}"
echo "       Output: ${OUTPUT}"
echo "       Vols  : ${OUTPUT_VOL}"

# --- SynthSR 출력 존재 확인 ---
if [[ ! -f "$INPUT" ]]; then
  echo "[ERR] SynthSR output not found: ${INPUT}" >&2
  echo "      Run 30_synthsr.sh first." >&2
  exit 1
fi

# --- 캐시 확인 ---
if [[ -f "$OUTPUT" && -f "$OUTPUT_VOL" && "${FORCE:-0}" != "1" ]]; then
  echo "[SKIP] SynthSeg output already exists."
  echo "       (set FORCE=1 to overwrite)"
  exit 0
fi

# --- Docker 실행 ---
echo "[RUN ] SynthSeg (${COMPOSE_OS} mode)"
${COMPOSE_CMD} run --rm synthseg \
  python /workspace/SynthSeg/scripts/commands/SynthSeg_predict.py \
  --i "/synthsr/${SID}_synthsr.nii.gz" \
  --o "/output/${SID}_synthseg.nii.gz" \
  --parc \
  --vol "/output/${SID}_synthseg_vols.csv"

echo "[DONE] SynthSeg complete: ${OUTPUT}"
echo "       Volumes CSV: ${OUTPUT_VOL}"
