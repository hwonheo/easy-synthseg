#!/usr/bin/env bash
# 90_pipeline.sh — 전체 파이프라인 오케스트레이터
# 실행: ./scripts/90_pipeline.sh
# 환경: COMPOSE_OS=mac(기본) 또는 COMPOSE_OS=linux
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

run_step() {
  local step="$1"
  local label="$2"
  echo ""
  echo "══════════════════════════════════════════"
  echo "  ${label}"
  echo "══════════════════════════════════════════"
  bash "${SCRIPT_DIR}/${step}"
}

# ── Step 00: 환경 체크 ──────────────────────────────────
if [[ -f "${SCRIPT_DIR}/00_env_check.sh" ]]; then
  run_step "00_env_check.sh" "[00] 환경 체크"
fi

# ── Step 10: DICOM → NIfTI ──────────────────────────────
run_step "10_dicom2nifti.sh" "[10] DICOM → NIfTI 변환"

# ── Step 20: NIfTI 후보 선택 ───────────────────────────
run_step "20_select_nifti.sh" "[20] NIfTI 후보 선택"

# selected_input.txt에서 SELECTED_NII 읽기
source "$(dirname "$0")/_common.sh"
if [[ -f "${LOG_DIR}/selected_input.txt" ]]; then
  SELECTED_NII="$(grep '^SELECTED=' "${LOG_DIR}/selected_input.txt" | cut -d= -f2)"
  export SELECTED_NII
fi

# ── Step 30: SynthSR ────────────────────────────────────
run_step "30_synthsr.sh" "[30] SynthSR (Super-Resolution)"

# ── Step 40: SynthSeg ───────────────────────────────────
# mac: 네이티브 ARM64 (tensorflow-metal, CPU fallback)
# linux: Docker 기반 (GPU)
if [[ "${COMPOSE_OS:-mac}" == "linux" ]]; then
  run_step "40_synthseg.sh" "[40] SynthSeg (Docker, Linux GPU)"
else
  run_step "40_synthseg_native.sh" "[40] SynthSeg (Native, ARM64)"
fi

# ── Step 50: FastSurfer (조건부) ────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  [50] FastSurfer (선택 사항)"
echo "══════════════════════════════════════════"
echo "  FastSurfer는 3D T1 + 헤더 안전 파일에서만 유효합니다."
read -rp "  FastSurfer를 실행하시겠습니까? [y/N]: " yn
if [[ "$yn" =~ ^[Yy]$ ]]; then
  bash "${SCRIPT_DIR}/50_fastsurfer.sh"
else
  echo "[SKIP] FastSurfer skipped."
fi

# ── 완료 요약 ───────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════"
echo "  Pipeline Complete"
echo "══════════════════════════════════════════"
echo ""
source "$(dirname "$0")/_common.sh"
echo "  SID        : ${SID}"
echo "  SynthSR    : ${SYNTHSR_DIR}/${SID}_synthsr.nii.gz"
echo "  SynthSeg   : ${SYNTHSEG_DIR}/${SID}_synthseg.nii.gz"
echo "  FastSurfer : ${FASTSURFER_DIR}/${SID}/"
echo "  Log        : ${LOG_DIR}/selected_input.txt"
echo ""
