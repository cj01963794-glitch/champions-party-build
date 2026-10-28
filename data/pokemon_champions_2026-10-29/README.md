# Pokémon Champions M-7 싱글 — 결정력·내구 조회 DB (2026-10-29)

## 데이터 출처와 범위

- 출처: [Lerisia/damage-calc](https://github.com/Lerisia/damage-calc), 커밋 [359f6eda062eaa1a8cfef530543da4b1b28a20bc](https://github.com/Lerisia/damage-calc/commit/359f6eda062eaa1a8cfef530543da4b1b28a20bc)
- 통계 시점: **2026-10-28 / 시즌 M-7 / 싱글**, `assets/champions_usage.json`의 기술 및 성격·SP 배치 자료
- **346종**, 각 종의 도감 기본 종족값/타입/대표 특성/대표 SP·성격/스피드·내구의 표준 투자 단계, **주력 기술 3,417개 기록**
- 결정력: 원본 `lib/views/dex/sections.dart`의 표준 3개 투자 단계 + `lib/calc/offensive_calculator.dart`·`ability_effects.dart`의 상수·통상 보정 규칙을 **사전 산출**한 숫자.
- 내구: 같은 코드의 `DefensiveCalculator.calculate` 표준 4개 투자 단계에서 **HP×실효 방어/0.411** 또는 **HP×실효 특방/0.411**.
- 이 DB는 사이트 화면을 직접 스크레이핑해 숫자를 베껴온 것이 **아니라**, 공개 도감/기술/통계 JSON에 공개 계산 코드를 **부분 재현**하여 생성한 것. 원본의 모든 조건부 상호작용을 실행·검증한 것은 **아님**.

## 더 빠른 경량 조회 (2026-10-29 추가)

- [fast_project.json](fast_project.json) — 자주 비교하는 **20종**의 결정력·내구·스피드·타입·특성 등 필수 조회 정보를 약 **18,990자**로 압축. 기존 `hotset_project.json` 약 42,523자 대비 56% 감소.
- [fast_all.json](fast_all.json) — M-7 싱글 **346종**의 같은 필수 정보를 약 **334,651자**로 압축. 기존 `db.json` 약 767,125자 대비 57% 감소.
- 빠른 파일들은 수치뿐 아니라 `type`, `ability`, `bulk`별 `[HP, B, D, 물리내구, 특수내구]`를 보존한다. 기존 DB와 **모든 3,417개 기술 항목·1,384개 내구 항목을 교차 검증**해 값 일치 확인.
- `moves`는 공간 절약을 위해 `[English, 한국어, 무보정 결정력, 32SP 결정력, 32SP+상승성격 결정력, status]`의 배열이며, `null`은 조건부/변화기 등으로 수치 보류된 항목을 뜻한다.
- **성능 한계:** 두 파일을 만들었다고 원격 GitHub 조회가 사라지는 것은 아니다. 채팅에서 조회할 때는 우선 `fast_project.json` 하나만 읽고, 그 밖의 대상은 `fast_all.json`을 읽으면 외부 파일 호출을 줄일 수 있다. 앱/프로젝트에 로컬 파일로 첨부하거나 별도 실행 프로세스에서 메모리 캐시하면 원격 호출 시간을 더 줄일 수 있다. ChatGPT 대화 사이에 상주하는 메모리 캐시가 생긴 것은 아니다.

## 빠른 조회

1. 프로젝트에서 많이 쓰는 20종(메가메타그로스·포푸니크·메가루카리오Z·메가라이츄Y·개굴닌자·마스카나·에이스번·메가캥카·메가플라엣테 등): [hotset_project.json](hotset_project.json) **파일 하나만 읽으면 됨**.
2. 그 밖의 포켓몬: [index.json](index.json)의 `byAlias`에 한국어 이름/별칭 검색 → `byEnglish[영문명].shard` → 해당 [shards/](shards/) 분할 파일에서 포켓몬 1종 추출.
3. 전체 데이터: [db.json](db.json) (단일 파일, 무거움); CSV 다운로드: [power.csv](power.csv), [bulk.csv](bulk.csv), [speed.csv](speed.csv).
4. 포켓몬별 터미널 조회: `python lookup.py 메메타 사이코팽`; 또는 `python lookup.py 개굴닌자`. 저장소를 클론했다면 외부 접속 없이 작동.

## 결정력 항목

`db.json`의 `pokemon["Mega Metagross"].moves`, `power.csv`의 해당 이름 행을 보면:

| 포켓몬 | 기술 | 무보정 | A32 / 성격 무보정 | A32 / 고집 |
|---|---|---:|---:|---:|
| 메가메타그로스 | 사이코팽 | 27,349 | 32,653 | **35,803** |
| 메가메타그로스 | 불릿펀치 | 12,870 | 15,366 | **16,848** |

- `uninvested`: 공격·특공(바디프레스는 방어) **0 SP, 성격 무보정**.
- `invested`: 해당 능력치 **32 SP, 성격 무보정**.
- `natureBoosted`: 해당 능력치 **32 SP, 상승 성격** (고집/조심/장난꾸러기 등 해당 기술 분류).
- 자속, 해당 종의 기본 특성, 4096분모 고정소수점 보정(단단한발톱 등) 포함.
- 원본 도감 비교표와 마찬가지로 **대전 상대의 타입 상성은 미포함**.
- 기본 메가스톤을 제외한 임의 도구, 벽·급소 토글·상대 특성·랭크·피해를 받은 체력·대타출동 등의 **전투 상태는 포함하지 않음**.
- `defaultSp`/대표 성격은 **참고용**으로 각 종에 수록하였으며 위 3개 표준 결정력 단계 자체에는 사용하지 않음.
- 일부 **확정급소 기술**의 실제 피해량과 도감의 기본 결정력 표시는 다를 수 있음. 실제 KO 판정에는 별도 데미지 계산 필요.

### 계산 신뢰도(`moves[].status`)

| 상태 | 뜻 |
|---|---|
| `reproduced_static` | 정적 위력/배율을 공개 공식과 원본 코드에서 재현한 값. *실제 웹 화면 대조 인증은 아님* |
| `explicit_max_hits` | 원본 도감의 연속기 기본값인 **최대 타수**로 계산. 실제 실전 타수는 달라질 수 있음 |
| `context_assumption` / `field_assumption` | 상태·상대 조건 또는 자동 필드·날씨를 일정하게 가정하고 산출 |
| `ability_condition_unchecked` / `special_move_unchecked` | 아직 모든 능력·기술 변환을 재현하지 않아 **잠정적인 참고치** |
| `requires_context` | 변화기, 상대 체중·스피드·현재 HP 등 필수 정보가 없거나 고정 피해 등으로 **결정력 숫자 미제공** |

**주의:** `status`가 `reproduced_static`이어도 게임 실행과 완전한 검증으로 ‘모든 경우에 정확하다’고 보장하는 것은 아님. 다만 숫자를 매번 재계산하지 않고 조회할 수 있게 만들었으며, 값의 근거를 추적 가능하게 관리함.

## 내구 항목

내구 수치 `bulk`/CSV의 기준:

- `none`: H0/B0/D0 (성격 무보정)
- `H32`: H32/B0/D0
- `HB32`: H32/B32 (방어 상승 성격), 특방은 H32 수치
- `HD32`: H32/D32 (특방 상승 성격), 방어는 H32 수치

정적 방어·특방 특성 및 모래바람에서 바위 타입 특방, 눈에서 얼음 타입 방어 보정을 적용. **멀티스케일·파동의방호·두꺼운지방 등 피해량에 직접 관여하는 특성은 내구 지표에 자동 환산되지 않는다.** 그런 상대와의 실전 피해량은 별도 시뮬레이션 필요.

## 저장 구조

- `db.json`: 전체 346종 결정력·내구·스피드·주력 기술·통계의 통합 DB
- `index.json`: 한글 이름·약칭·영문명 → 영문 ID → 분할 파일 경로
- `shards/00.json` ~ `07.json`: 빠른 조회용 분할 데이터
- `hotset_project.json`: 이번 팀 구축 프로젝트의 20종 (빠른 조회용)
- `hotset_top50.json`: 싱글 사용순위 상위 50종
- `power.csv` / `bulk.csv` / `speed.csv`: 분석·필터링용 CSV
- `source_champions_usage.json`: 원본 시즌 싱글 통계 스냅샷
- `source_pokemon_part1.json`, `source_pokemon_part2.json`: 원본 도감 데이터 보관
- `source_moves_part1.json`, `source_moves_part2.json`: 원본 기술 데이터 보관
- `lookup.py`: 로컬 간편 조회 스크립트
- `verify.py`: 파일 일관성 및 메가메타그로스 표본 검증 스크립트

## 갱신 규칙

새 시즌의 통계로 자동 갱신되는 시스템은 **아직 아님**. 최신 시즌을 적용할 때 `source_champions_usage.json` 갱신, 도감 및 계산 코드의 변화 확인, 수치 재산출, 표본 대조가 필요함. 기존 DB를 조용히 최신 데이터라고 주장하지 말 것.
