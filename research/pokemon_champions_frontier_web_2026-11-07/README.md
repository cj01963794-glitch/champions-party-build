# Pokémon Champions — Frontier 웹 클라이언트 AI·데이터 보존본

**수집일:** 2026-11-07 (KST) · **대상:** https://pokemon-tower-battle.rotatedtriangle.chatgpt.site/

이 폴더는 포챔스 싱글 3v3 파티 연구를 위해 사용자 제공 Chrome DevTools HAR 세 건에서 추출한 **실제로 브라우저로 전달된 공개 실행 코드 및 게임 데이터의 연구용 스냅샷**이다. 사이트의 전체 개발 원본 저장소 또는 서버 내부 코드를 의미하지 않는다.

## 파일 안내

- `frontier_runtime_source_and_game_data_2026-11-07.tar.gz` — HTML, 브라우저 실행 JS **9개**, 사이트가 실제 전달한 `game-content` JSON (트레이너 개별 JSON **201개** 포함), 기타 로케일 JSON; 이미지·음악·동영상·CSS는 제외. 압축 해제 후 원래의 상대 경로가 보존된다.
- `ai-handler.js` — 개별 열람용 AI 판단 엔진 파일 (`assets/workers/ai-handler.js`의 동일 바이트)
- `battle-handler.js` — 추가 배틀 HAR에서 확보한 워커 (`assets/workers/battle-handler.js`)
- `runtime.worker.js`, `entry-selection.js` — 워커/선출 로딩 경로 파악을 위한 개별 파일
- `TRAINER_SETS_1206.csv` — 201 트레이너 × 6마리의 기술·특성·도구·성격·투자 수치를 하나의 CSV로 변환한 자료. **실제 랭크배틀 사용률 자료가 아님.**
- `SOURCE_MANIFEST.tsv` — 아카이브 원본 파일별 크기와 SHA-256
- `HAR_PATH_INVENTORY.tsv` — HAR의 해당 사이트 요청 경로만 발췌한 정보(요청 파라미터·쿠키·헤더 제외)
- `ANALYSIS_AND_LIMITATIONS.md` — 기술적 분석 결과, 검증 상태, 후속 작업
- `CONVERSATION_NOTES_2026-11-07.md` — 사용자 요청·대화 진행 기록(요약본; 원문 전사 아님)

## 사실로 확인한 범위

- HAR: JS-only 8건 / 초기 전체 322건 / 배틀 중 414건. 응답 상태값은 각 파일에서 200으로 기록됨.
- `game-content/current.json`: `2026-11-03.1`
- 게임 DB: 포켓몬 1367종(폼/엔트리 포함), 기술 934개, 특성 323개, 도구 956개 항목.
- 트레이너 201명과 파티 세트 1,206개 (각 6마리).
- 브라우저 JS: 9개. 전투 엔진 번들 `assets/workers/observation.js`도 원본 바이트로 아카이브에 들어 있음. `battle-handler.js` 포함.
- 이 파일은 공개 사이트의 클라이언트 자료이며, 올포타 Ruby AI 원본과 별도로 취급한다.

## 외부 관련 자료

- 동일 연구 저장소의 [`research/pokemon_tower_ai_v2_1003/`](../pokemon_tower_ai_v2_1003/) — 사용자가 2026-07-16 게시글에서 다운로드한 **올포타 개선 Ruby AI**의 이전 보존본. 파일명 `v2_1003`을 2026-10-03 배포일이라고 해석하면 **오류**임.
- [erablah/gouppokemontower-improved-battle-ai](https://github.com/erablah/gouppokemontower-improved-battle-ai) — 2026-05-12 공개 main 커밋을 확인한 관련 개선 AI 저장소. 웹사이트의 실제 원본 GitHub 저장소라고 확인된 것은 아님.
- [포챔스 배틀타워 소개글](https://gall.dcinside.com/mgallery/board/view/?id=rayquaza&no=245573) — 2026-11-04 게시글로 앞선 대화에서 소개됨. 글의 내용과 계정 연결은 추가 독립 검증이 필요함.

## 안전·권리

- **원본 HAR은 공개 저장소에 올리지 않았다.** HAR에는 세션 쿠키·인증 헤더·요청 본문 등 민감한 정보가 들어갈 수 있다. 여기에는 해당 사이트가 배포한 실행 파일과 게임 콘텐츠만 저장했다.
- 제3자 개발 코드·콘텐츠의 원저작권 및 라이선스는 사용자에게 이전된 것이 아니다. 이 스냅샷은 연구 보관용으로 기록한다. 재배포와 재사용 시 원저작자의 이용 허락 조건을 별도로 확인해야 한다.
- 실행 정확성·룰 일치·AI 장기전 성능에 대한 보증은 없다. 별도 테스트 전에는 **정적 분석 자료**로 취급한다.