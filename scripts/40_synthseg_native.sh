#!/usr/bin/env bash
# 40_synthseg_native.sh — SynthSeg 네이티브 실행 (Mac ARM64, tensorflow-metal CPU)
# 입력: ${SYNTHSR_DIR}/${SID}_synthsr.nii.gz
# 출력: ${SYNTHSEG_DIR}/${SID}_synthseg.nii.gz
#        ${SYNTHSEG_DIR}/${SID}_synthseg_vols.csv
#
# macOS ARM64 기본 경로. Linux/GPU 환경에서는 40_synthseg.sh (Docker)를 사용.
# 환경 준비: scripts/setup_tf_metal_env.sh
set -euo pipefail

source "$(dirname "$0")/_common.sh"

# --- 경로 설정 ---
SYNTHSEG_SRC="${PROJECT_ROOT}/synthseg_src"
RUNNER="${SYNTHSEG_SRC}/run_native_test.py"
INPUT="${SYNTHSR_DIR}/${SID}_synthsr.nii.gz"
OUTPUT="${SYNTHSEG_DIR}/${SID}_synthseg.nii.gz"
OUTPUT_VOL="${SYNTHSEG_DIR}/${SID}_synthseg_vols.csv"
CONDA_ENV="synthseg-metal"

echo "[INFO] SynthSeg Native (ARM64, tensorflow-metal)"
echo "       Input : ${INPUT}"
echo "       Output: ${OUTPUT}"
echo "       Vols  : ${OUTPUT_VOL}"

# --- SynthSR 출력 존재 확인 ---
if [[ ! -f "$INPUT" ]]; then
  echo "[ERR] SynthSR output not found: ${INPUT}" >&2
  echo "      Run 30_synthsr.sh first." >&2
  exit 1
fi

# --- conda 환경 확인 ---
if ! conda env list 2>/dev/null | grep -q "^${CONDA_ENV}[[:space:]]"; then
  echo "[ERR] conda env '${CONDA_ENV}' not found." >&2
  echo "      Run: bash scripts/setup_tf_metal_env.sh" >&2
  exit 1
fi

# --- SynthSeg 소스 확인 ---
if [[ ! -f "$RUNNER" ]]; then
  echo "[ERR] run_native_test.py not found: ${RUNNER}" >&2
  exit 1
fi

# --- 캐시 확인 ---
if [[ -f "$OUTPUT" && -f "$OUTPUT_VOL" && "${FORCE:-0}" != "1" ]]; then
  echo "[SKIP] SynthSeg output already exists."
  echo "       (set FORCE=1 to overwrite)"
  exit 0
fi

# --- 실행 ---
echo "[RUN ] SynthSeg Native"
TIME_START=$(date +%s)

conda run -n "${CONDA_ENV}" --no-capture-output \
  python3 "${RUNNER}" \
  --i "${INPUT}" \
  --o "${OUTPUT}" \
  --parc \
  --vol "${OUTPUT_VOL}"

TIME_END=$(date +%s)
ELAPSED=$((TIME_END - TIME_START))

echo "[DONE] SynthSeg complete: ${OUTPUT}"
echo "       Volumes CSV : ${OUTPUT_VOL}"
echo "       Total time  : ${ELAPSED}s"
