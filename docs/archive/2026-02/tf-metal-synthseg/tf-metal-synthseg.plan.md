# Plan: tf-metal-synthseg

## 목표

SynthSeg를 Docker(CPU, x86 에뮬레이션) 방식에서 **macOS 네이티브 + tensorflow-metal(Metal GPU)** 방식으로 전환하는 실험 브랜치를 구성하고, 성능을 비교한다.

## 핵심 전제 조건 (중요)

`tensorflow-metal`은 **macOS 전용 플러그인**이다.
Linux/arm64 Docker 컨테이너 안에서는 동작하지 않는다.
→ SynthSeg를 Docker 밖, **Mac 호스트에서 직접 실행**하는 구조로 변경 필요.

## 현재 구조 vs 목표 구조

| 항목 | 현재 (Docker) | 목표 (Native Metal) |
|------|--------------|---------------------|
| 실행 환경 | Docker `pwesp/synthseg:py38` | Mac 호스트 Python venv |
| 플랫폼 | `linux/amd64` (Rosetta 에뮬레이션) | `macOS arm64` (네이티브) |
| GPU | 사용 불가 (CPU fallback) | Metal GPU 사용 |
| TF 버전 | TensorFlow 2.x (Keras 레거시) | tensorflow-macos + tensorflow-metal |
| 진입점 | `40_synthseg.sh` (Docker run) | `40_synthseg_native.sh` (호스트 python) |

## 스코프 (이 실험에서 할 것 / 하지 않을 것)

### 포함
- [ ] 호스트에 SynthSeg 네이티브 실행 환경 구성 (conda/venv)
- [ ] `tensorflow-macos` + `tensorflow-metal` 설치 및 동작 확인
- [ ] SynthSeg weights/코드를 호스트에서 직접 실행
- [ ] 신규 스크립트 `40_synthseg_native.sh` 작성
- [ ] 기존 Docker 방식과 성능 비교 (처리 시간, Metal 인식 여부)

### 제외
- [ ] SynthSeg 모델 구조 변경 (가중치 그대로 사용)
- [ ] FastSurfer MLX 포팅 (별도 브랜치에서 진행)
- [ ] 프로덕션 파이프라인 교체 (실험 브랜치만)

## 기술 스택

| 구성요소 | 버전/패키지 |
|---------|------------|
| Python | 3.10 (miniforge, arm64) |
| tensorflow-macos | 2.12+ |
| tensorflow-metal | 1.0+ (Apple 공식 지원) |
| SynthSeg | pwesp/SynthSeg (GitHub, weights 재사용) |
| 환경 관리 | conda (miniforge) 또는 venv |

## 성공 기준

1. `tensorflow-metal`이 Metal GPU를 인식하는 로그 출력
2. SynthSeg가 호스트에서 segmentation 완료
3. Docker 방식 대비 처리 시간 측정값 존재
4. 결과 NIfTI가 Docker 방식 출력과 동일 (diff 검증)

## 브랜치 전략

```
main (현재 스터디)
└── experiment/tf-metal-synthseg  ← 이 실험
    ├── scripts/40_synthseg_native.sh  (신규)
    ├── scripts/setup_tf_metal_env.sh  (환경 설치 스크립트)
    └── docs/  (실험 결과 기록)
```

## 단계별 작업 계획

### Step 1. 브랜치 생성 및 환경 확인
- `experiment/tf-metal-synthseg` 브랜치 생성
- Mac Apple Silicon 확인 (`uname -m` → `arm64`)
- miniforge 설치 여부 확인

### Step 2. Python 환경 구성
- `conda create -n synthseg-metal python=3.10`
- `pip install tensorflow-macos tensorflow-metal`
- Metal 인식 확인 스크립트 실행

### Step 3. SynthSeg 호스트 실행 환경 구성
- SynthSeg 소스 + 가중치 준비 (Docker 이미지에서 추출 or GitHub)
- 의존성 설치 (`keras`, `nibabel`, `numpy` 등)
- 단독 실행 테스트

### Step 4. 스크립트 작성
- `40_synthseg_native.sh`: 호스트 Python으로 SynthSeg 실행
- `scripts/setup_tf_metal_env.sh`: 환경 설치 자동화

### Step 5. 성능 비교
- 동일 입력으로 Docker 방식 / Native Metal 방식 각 3회 실행
- 처리 시간 기록
- 출력 NIfTI 비교

## 리스크

| 리스크 | 가능성 | 대응 |
|--------|--------|------|
| SynthSeg가 특정 TF 버전에 종속 | 중 | requirements 고정, 버전 매핑 테스트 |
| tensorflow-metal이 3D conv에서 오작동 | 중 | CPU fallback 옵션 유지 |
| SynthSeg weights 추출 어려움 | 하 | Docker 이미지에서 `cp` 로 추출 |
| 결과 NIfTI 수치 차이 | 중 | 허용 오차(FP32 vs Metal 정밀도) 명시 |

## 예상 소요 시간

| 단계 | 예상 |
|------|------|
| 환경 구성 | 1~2시간 |
| 스크립트 작성 | 2~3시간 |
| 성능 비교 | 1시간 |
| 문서화 | 1시간 |

---

작성일: 2026-02-27
브랜치: `experiment/tf-metal-synthseg`
상태: Plan
