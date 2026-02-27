#!/usr/bin/env python3
"""SynthSeg Native Metal 실행 테스트 - SynthSeg_predict.py CLI 래퍼"""
import sys
import os
import time

# SynthSeg CLI 스크립트를 직접 실행 (sys.argv 그대로 전달)
# 사용법: python run_native_test.py --i <input> --o <output> --vol <csv> [--parc]

SYNTHSEG_SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "SynthSeg")
CLI_SCRIPT = os.path.join(SYNTHSEG_SRC, "scripts", "commands", "SynthSeg_predict.py")

# sys.argv[0]를 CLI 스크립트로 교체 (SynthSeg_predict.py가 sys.argv[0]로 경로를 계산함)
sys.argv[0] = CLI_SCRIPT

import tensorflow as tf

gpus = tf.config.list_physical_devices("GPU")
print(f"[INFO] TF version : {tf.__version__}")
print(f"[INFO] Metal GPU  : {gpus[0].name if gpus else 'None (CPU only)'}")

# Keras 2.13+ FusedBatchNorm 5D → TF/Metal 미지원 문제 우회
# BatchNormalization._fused_can_be_used를 monkey-patch하여 5D 비활성화
import keras.src.layers.normalization.batch_normalization as _bn_mod

_orig_fused_can_be_used = _bn_mod.BatchNormalizationBase._fused_can_be_used

def _patched_fused_can_be_used(self, ndims=None):
    if ndims == 5:
        return False  # 5D (3D 볼륨) FusedBatchNorm 비활성화
    if ndims is None:
        return _orig_fused_can_be_used(self)
    return _orig_fused_can_be_used(self, ndims)

_bn_mod.BatchNormalizationBase._fused_can_be_used = _patched_fused_can_be_used
print(f"[INFO] BatchNorm 5D fused: patched (disabled)")

t0 = time.time()

# SynthSeg CLI 스크립트 실행
with open(CLI_SCRIPT) as f:
    exec(compile(f.read(), CLI_SCRIPT, "exec"))

elapsed = time.time() - t0
print(f"[DONE] Inference time: {elapsed:.1f}s")
