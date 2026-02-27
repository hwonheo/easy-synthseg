#!/usr/bin/env bash
# setup_tf_metal_env.sh — synthseg-metal conda 환경 초기 설치 스크립트
# 실험 브랜치: experiment/tf-metal-synthseg
#
# 사용법:
#   bash scripts/setup_tf_metal_env.sh
#
# 요구사항:
#   - Apple Silicon Mac (arm64)
#   - miniforge 설치 완료 (brew install miniforge)
set -euo pipefail

CONDA_ENV="synthseg-metal"
PYTHON_VERSION="3.10"
TF_VERSION="2.15.1"
TF_METAL_VERSION="1.1.0"
KERAS_VERSION="2.15.0"

echo "[INFO] tensorflow-metal 환경 설치"
echo "       conda env : ${CONDA_ENV}"
echo "       Python    : ${PYTHON_VERSION}"
echo "       TF        : ${TF_VERSION}"
echo "       Metal     : ${TF_METAL_VERSION}"

# --- 아키텍처 확인 ---
ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
  echo "[ERR] Apple Silicon (arm64) 전용 스크립트입니다. 현재: ${ARCH}" >&2
  exit 1
fi

# --- conda 확인 ---
if ! command -v conda &>/dev/null; then
  echo "[ERR] conda not found. miniforge를 먼저 설치하세요:" >&2
  echo "      brew install miniforge" >&2
  exit 1
fi

# --- 환경 생성 (이미 있으면 skip) ---
if conda env list | grep -q "^${CONDA_ENV}"; then
  echo "[SKIP] conda env '${CONDA_ENV}' 이미 존재합니다."
  echo "       재설치하려면: conda env remove -n ${CONDA_ENV} -y"
else
  echo "[RUN ] conda create -n ${CONDA_ENV} python=${PYTHON_VERSION}"
  conda create -n "${CONDA_ENV}" python="${PYTHON_VERSION}" -y
fi

# --- 패키지 설치 ---
echo "[RUN ] tensorflow + tensorflow-metal 설치"
conda run -n "${CONDA_ENV}" pip install \
  "tensorflow==${TF_VERSION}" \
  "tensorflow-metal==${TF_METAL_VERSION}" \
  "keras==${KERAS_VERSION}" \
  "nibabel" \
  "scipy"

# --- Metal GPU 인식 확인 ---
echo "[TEST] Metal GPU 인식 확인"
conda run -n "${CONDA_ENV}" python3 -c "
import tensorflow as tf
import keras
print('  TF    :', tf.__version__)
print('  Keras :', keras.__version__)
gpus = tf.config.list_physical_devices('GPU')
if gpus:
    print('  [OK] Metal GPU detected:', gpus[0].name)
else:
    print('  [WARN] GPU not detected - CPU only mode')
"

echo "[DONE] 환경 설치 완료: ${CONDA_ENV}"
echo "       실행: ./scripts/40_synthseg_native.sh"
