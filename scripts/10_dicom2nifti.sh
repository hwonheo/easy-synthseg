#!/usr/bin/env bash
# 10_dicom2nifti.sh — DICOM → NIfTI 변환 (캐시)
# 입력: ${DICOM_DIR}
# 출력: ${NIFTI_DIR}/*.nii.gz
set -euo pipefail

source "$(dirname "$0")/_common.sh"

echo "[INFO] DICOM → NIfTI"
echo "       Input : ${DICOM_DIR}"
echo "       Output: ${NIFTI_DIR}"

# --- 입력 디렉토리 확인 ---
if [[ ! -d "$DICOM_DIR" ]]; then
  echo "[ERR] DICOM directory not found: ${DICOM_DIR}" >&2
  echo "      Place DICOM files at ${DICOM_DIR}" >&2
  exit 1
fi

# --- 캐시 확인 ---
if ls "${NIFTI_DIR}"/*.nii* >/dev/null 2>&1 && [[ "${FORCE_CONVERT:-0}" != "1" ]]; then
  echo "[SKIP] NIfTI files already exist in ${NIFTI_DIR}"
  echo "       (set FORCE_CONVERT=1 to reconvert)"
  exit 0
fi

# --- dcm2niix 실행 ---
echo "[RUN ] dcm2niix"
dcm2niix -f "%d_%s" -z y -o "${NIFTI_DIR}" "${DICOM_DIR}"

echo "[DONE] Conversion complete: ${NIFTI_DIR}"
