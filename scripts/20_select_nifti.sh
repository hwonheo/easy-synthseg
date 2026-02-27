#!/usr/bin/env bash
# 20_select_nifti.sh — NIfTI 후보 선택 + 재현성 기록
# 입력: ${NIFTI_DIR}/*.nii*
# 출력: ${LOG_DIR}/selected_input.txt, 환경변수 SELECTED_NII (export)
set -euo pipefail

source "$(dirname "$0")/_common.sh"

BLACKLIST='(dwi|dti|adc|trace|swi|angio|tof|mra|spine|localizer|survey|t2|flair|fse|t2[-_]?gre|f[gk]re|gre|^PJN_[0-9]+_i[0-9]+|_i0*[0-9]{3,})'
WHITELIST_3D_T1='(t1w|mprage|bravo|spgr|tfe|fspoiled|3d.*t1|t1.*3d)'

# nibabel 유무 확인
HEADER_FILTER=1
if ! _have_nibabel; then
  HEADER_FILTER=0
  echo "[WARN] nibabel not found → header-based 2D/OOM filtering disabled."
  echo "       Install: python3 -m pip install nibabel"
fi

# 후보 수집 함수
collect_candidates() {
  local mode="$1"  # "3d" or "t1"
  local out=()
  local excluded=()

  for f in "${NIFTI_DIR}"/*.nii*; do
    [[ -e "$f" ]] || continue
    local name
    name="$(basename "$f")"

    # blacklist 제외
    echo "$name" | grep -qiE "$BLACKLIST" && continue

    # 모드별 whitelist
    if [[ "$mode" == "3d" ]]; then
      echo "$name" | grep -qiE "$WHITELIST_3D_T1" || continue
    else
      echo "$name" | grep -qiE '(t1)' || continue
    fi

    # 헤더 기반 위험 파일 제외
    if [[ "$HEADER_FILTER" == "1" ]] && _is_risky_2d "$f"; then
      excluded+=("$f")
      continue
    fi

    out+=("$f")
  done

  printf "%s\n" "${out[@]+"${out[@]}"}" | sort
  echo "-----EXCLUDED-----"
  printf "%s\n" "${excluded[@]+"${excluded[@]}"}" | sort
}

# 3D T1 후보 수집
mapfile -t lines < <(collect_candidates "3d")
candidates=(); excluded=(); in_ex=0
for line in "${lines[@]}"; do
  if [[ "$line" == "-----EXCLUDED-----" ]]; then in_ex=1; continue; fi
  [[ "$in_ex" == "0" ]] && candidates+=("$line") || excluded+=("$line")
done

fallback_mode=0
if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "[WARN] No 3D T1 candidates (mprage/bravo/spgr/tfe/3D/T1w) or all excluded."
  echo "       Falling back to generic 'T1' candidates."
  fallback_mode=1

  mapfile -t lines < <(collect_candidates "t1")
  candidates=(); excluded=(); in_ex=0
  for line in "${lines[@]}"; do
    if [[ "$line" == "-----EXCLUDED-----" ]]; then in_ex=1; continue; fi
    [[ "$in_ex" == "0" ]] && candidates+=("$line") || excluded+=("$line")
  done
fi

# 제외 파일 안내
if [[ ${#excluded[@]} -gt 0 ]]; then
  echo ""
  echo "=== Excluded (2D / thick-slice → FastSurfer OOM risk) ==="
  for f in "${excluded[@]}"; do
    [[ -n "$f" ]] && echo "  - $(basename "$f")"
  done
  echo "  Tip: 위 파일은 SynthSeg 전용으로만 사용하세요."
fi

if [[ ${#candidates[@]} -eq 0 ]]; then
  echo "[ERR] No suitable NIfTI candidates after filtering." >&2
  exit 1
fi

# 선택 메뉴
echo ""
echo "=== Select NIfTI for pipeline (SID=${SID}) ==="
for i in "${!candidates[@]}"; do
  printf "  [%d] %s\n" "$i" "$(basename "${candidates[$i]}")"
done

read -rp "Enter index: " idx
if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 0 || idx >= ${#candidates[@]} )); then
  echo "[ERR] Invalid selection." >&2
  exit 1
fi

SELECTED="${candidates[$idx]}"
echo "[OK  ] Selected: $(basename "$SELECTED")"

if [[ "$fallback_mode" == "1" ]]; then
  echo "[INFO] generic T1 후보 선택됨. 3D T1이 없을 경우 SynthSeg 우선이 안전합니다."
fi

# FastSurfer 안전 여부 판단 (기록용)
FS_SAFE="unknown"
if [[ "$HEADER_FILTER" == "1" ]]; then
  if _is_risky_2d "$SELECTED"; then
    FS_SAFE="risky"
  else
    FS_SAFE="safe"
  fi
fi

# 재현성 기록
cat > "${LOG_DIR}/selected_input.txt" <<EOF
# SID: ${SID}
# 선택일시: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# fastsurfer_safe: ${FS_SAFE}
SELECTED=${SELECTED}
EOF

echo "[LOG ] Selection recorded: ${LOG_DIR}/selected_input.txt"

# 90_pipeline.sh에서 읽을 수 있도록 export
export SELECTED_NII="${SELECTED}"
