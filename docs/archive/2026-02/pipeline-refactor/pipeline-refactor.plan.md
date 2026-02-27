# [Plan] pipeline-refactor

> FastSurfer Hybrid Mac/Linux 워크플로우 가이드 기반 파이프라인 리팩터링

## 1. 개요

### 목표
`FastSurfer_Hybrid_Mac_Linux_Workflow_Guide.md` 가이드에 정의된 권장 아키텍처에 맞춰
현재 단순 구조의 스크립트/Docker Compose 환경을 모듈화된 완전한 파이프라인으로 전환한다.

### 배경
현재 구현 상태 vs 가이드 권장 사항 간 주요 갭:
- SynthSR 단계 완전 누락 (30_synthsr.sh)
- SynthSeg가 SynthSR 출력 대신 원본 NIfTI를 직접 입력 받음
- 모놀리식 스크립트 (run_fastsurfer.sh) → 모듈 분리 필요
- .env가 DATA_ROOT 없이 절대경로 하드코딩
- derivatives/ 분리 없어 결과물이 혼재
- 로그 디렉토리 / 재현성 기록 없음

---

## 2. 요구사항

### 필수 (Must Have)

| ID | 요구사항 |
|----|---------|
| R-01 | DATA_ROOT 기반 .env 재구성 (파생 경로 자동화) |
| R-02 | SynthSR 스크립트 추가 (30_synthsr.sh) |
| R-03 | SynthSeg가 SynthSR 출력을 입력으로 받도록 수정 (40_synthseg.sh) |
| R-04 | 폴더 구조 재편: data/dicom/, data/nifti/, data/derivatives/, data/logs/ |
| R-05 | 스크립트 모듈화: scripts/ 하위 00~90 분리 |
| R-06 | Docker Compose 재구성: compose/ 하위 common + os별 분리 |

### 선택 (Should Have)

| ID | 요구사항 |
|----|---------|
| R-07 | 전체 파이프라인 오케스트레이터 (90_pipeline.sh) |
| R-08 | 환경 체크 스크립트 (00_env_check.sh) |
| R-09 | 선택 결과 기록 (data/logs/$SID/selected_input.txt) |

### 제외 (Won't Have)

- FreeSurfer 전체 설치 (라이선스 경로만 마운트)
- Web UI / 자동화 스케줄러

---

## 3. 구현 범위

### 파일 구조 (목표)

```
fastsurfer-docker/
├── .env                          ← DATA_ROOT 기반 재작성
├── .env.example
├── compose/
│   ├── docker-compose.common.yml ← synthseg + freesurfer + fastsurfer 서비스 정의
│   ├── docker-compose.mac.yml    ← amd64 + user:0:0 + allow_root
│   └── docker-compose.linux-gpu.yml ← GPU 예약
├── scripts/
│   ├── 00_env_check.sh
│   ├── 10_dicom2nifti.sh
│   ├── 20_select_nifti.sh
│   ├── 30_synthsr.sh             ← 신규
│   ├── 40_synthseg.sh            ← SynthSR 출력 입력으로 수정
│   ├── 50_fastsurfer.sh          ← run_fastsurfer.sh 분리
│   └── 90_pipeline.sh            ← 신규 오케스트레이터
└── data/
    ├── dicom/subjectX/
    ├── nifti/subjectX/
    ├── derivatives/subjectX/
    │   ├── synthsr/
    │   ├── synthseg/
    │   └── fastsurfer/
    └── logs/subjectX/
```

### 파이프라인 흐름 (목표)

```
[00] 환경 체크
  ↓
[10] DICOM → NIfTI (캐시: 이미 있으면 스킵)
  ↓
[20] 후보 선택 → logs/$SID/selected_input.txt 기록
  ↓
[30] SynthSR (mri_synthsr) → derivatives/$SID/synthsr/
  ↓
[40] SynthSeg (SynthSR 출력 입력) → derivatives/$SID/synthseg/
  ↓
[50] FastSurfer (선택적: 3D T1 + 헤더 안전 시만) → derivatives/$SID/fastsurfer/
```

---

## 4. 구현 우선순위

### Phase 1 — 핵심 파이프라인 정정 (즉시)
1. .env 재구성 (R-01)
2. SynthSR 스크립트 신규 작성 (R-02)
3. SynthSeg 입력 수정 (R-03)

### Phase 2 — 구조 재편 (단기)
4. 폴더 구조 재편 (R-04)
5. 스크립트 모듈화 (R-05)

### Phase 3 — Compose 및 오케스트레이션 (중기)
6. Docker Compose 재구성 (R-06)
7. 파이프라인 오케스트레이터 (R-07)
8. 환경 체크 + 로그 기록 (R-08, R-09)

---

## 5. 위험 요소

| 위험 | 영향 | 대응 |
|------|------|------|
| SynthSR용 FreeSurfer 이미지 크기 | 빌드/다운로드 시간 증가 | pwesp/synthseg 또는 freesurfer/freesurfer 중 선택 필요 |
| macOS ARM에서 mri_synthsr 실행 속도 | 느릴 수 있음 (amd64 에뮬레이션) | 가이드대로 "단발 검증"으로 허용 |
| 기존 data/ 구조 마이그레이션 | NIFTI_OUT에 245개 파일 혼재 | 스크립트로 자동 이동 or 병행 운용 |

---

## 6. 완료 기준

- [ ] `./scripts/90_pipeline.sh` 실행 시 전체 파이프라인 (10→20→30→40→[50]) 완료
- [ ] SynthSeg 입력이 SynthSR 출력(`*_synthsr.nii.gz`)임을 검증
- [ ] `data/derivatives/$SID/` 하위에 synthsr/, synthseg/ 결과 저장 확인
- [ ] `data/logs/$SID/selected_input.txt` 생성 확인
- [ ] Mac(amd64) + Linux(GPU) 양쪽에서 Compose 분기 정상 동작

---

**작성일**: 2026-02-26
**상태**: Plan
