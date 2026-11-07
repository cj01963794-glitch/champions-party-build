# 코드 분석과 확인되지 않은 부분 (2026-11-07)

## 검증한 소스 경로

브라우저 워커 및 앱의 주요 JS 9개 (9개는 수집된 HTML/JS 중 확인된 숫자):

- `assets/battle.js` — 85,096 bytes
- `assets/entry-selection.js` — 3,337 bytes
- `assets/index.js` — 595,824 bytes
- `assets/workers/ai-handler.js` — 189,967 bytes
- `assets/workers/battle-handler.js` — 2,453 bytes
- `assets/workers/content.js` — 5,935 bytes
- `assets/workers/observation.js` — 6,825,814 bytes
- `assets/workers/rolldown-runtime.js` — 345 bytes
- `assets/workers/runtime.worker.js` — 421 bytes

JSON 240개(개별 트레이너 201개 + 나머지 39개), HTML 1개가 아카이브에 포함된다. CSS·오디오·이미지·애니메이션 리소스는 목적에 맞지 않아 제외했다. 단 `media.json` 같은 **참조 메타데이터**는 JSON이라 포함했다.

## AI 코드에서 확인·언급된 함수

- `assets/workers/ai-handler.js`: `decide`, `duel`, `replacementDuel`, `switchScores`, `chooseWeighted`, `selectEntries` 등 AI 평가·선택 경로가 확인됐다는 이전 분석 내용. 실제 매개변수/호출 빈도는 향후 함수별 검증 필요.
- `assets/workers/observation.js`: 약 6.8 MB, Pokémon Showdown 기반 전투 코드가 포함된 클라이언트 번들로 파악. 기초 엔진이 랭크배틀 포챔스의 현재 룰과 모든 기술·메가·선공기에서 동일하게 작동하는지는 검증 안 됨.
- `assets/workers/battle-handler.js`: 약 2.5 KB, 배틀 HAR에서 새로 확보.
- `game-content/2026-11-03.1/trainers/*.json`: 실제 사이트에서 전달된 201개 트레이너 파티 샘플.

## 현재의 증거 수준

| 질문 | 현재 답변 |
|---|---|
| AI·배틀 주요 JS는 확보했는가? | **확인된 9개 파일 확보**. 코드 의존성 전수 탐색 및 모든 기능의 동적 검증은 미완료 |
| AI 결정·선출·교체 코드를 읽을 수 있는가? | **가능**. `ai-handler.js` 등 포함 |
| 대전 결과를 오프라인에서 동일하게 재현했는가? | **아니오**. 엔진 구동·랜덤 시드 통제·행동 비교 미실시 |
| 3v3 장기 사이클을 탐색하는가? | **확인 안 됨**. 현재 AI의 대면 시뮬레이션을 20턴 전역 최적화라고 간주 금지 |
| 원본 GitHub 저장소를 찾았는가? | **아니오**. 관련 Ruby AI 저장소만 확인 |
| 사이트의 서버 코드/비공개 개발 원본을 확보했는가? | **아니오** |
| 원본 HAR을 포함했는가? | **아니오**. 세션 정보 노출을 예방하기 위해 제외 |

## 올포타 Ruby AI와의 관계

별도 저장된 올포타 Ruby AI 및 웹 JS AI에 `100`, `-999`, `95/70`, 최대 10턴/교체 4턴, 기습 30% 등 판단 상수가 대응한다는 **앞선 정적 분석 진술**이 있었다. 공통점은 이식 가능성을 뒷받침하지만, *코드가 동일하다는 입증이나 플레이 재현 실험은 아니다*. 이 수치 비교는 코드 위치·호출 경로를 재확인하고 기록하기 전까지 잠정 관찰로 남긴다.

## 후속 검증 권고

1. 재귀적 정적 의존성(`import`, `fetch`, Worker, 런타임 에셋)을 열람해 미확보 JS/JSON을 확인.
2. AI 독립 실행 하네스 구현: 동일 전투 상태·같은 난수 시드 입력 시 같은 행동·점수 나오는지 비교.
3. `TRAINER_SETS_1206.csv`와 프로젝트 M6/M7 상위권 통계 간 형태·기술 분포 차이 분리. 트레이너 샘플을 랭크배틀 채용률로 대체하지 않기.
4. 1대1 유리와 3v3 승리 차이, 교체 시 피해·선공권·랭크업·잔류를 포함한 턴별 케이스로 검증.
5. 코드가 로컬에서 동작한다는 증거 없이 반복 대전 시스템이 완성됐다고 단정하지 않기.