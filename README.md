# 포켓몬 챔피언즈 파티 구축 철학

포켓몬 챔피언즈에서 **강한 파티란 무엇인가**, 그리고 **어떤 기준으로 파티를 설계하고 평가할 것인가**를 지속적으로 발전시키기 위한 독립 문서 저장소입니다.

이 저장소는 기존 `champions-singles-lab`(배틀 AI / 계산기 개발)과 별개입니다. 게임 데이터나 특정 파티의 정답을 저장하는 곳이 아니라, 파티 구축에 적용할 **판단 원칙과 사고 과정**을 기록합니다.

## 문서 안내

- [`docs/TEAM_BUILDING_PHILOSOPHY.md`](docs/TEAM_BUILDING_PHILOSOPHY.md): 현재 채택한 파티 구축 철학과 평가 기준 (수정 대상)
- [`docs/archetypes/REVIVAL_TRADE_PAWMOT.md`](docs/archetypes/REVIVAL_TRADE_PAWMOT.md): 필수 전개파티 03 — 다크펫·빠르모트 부활·성묘/총대장 및 변형군
- [`docs/archetypes/PSYCHIC_TERRAIN_BLASTOISE.md`](docs/archetypes/PSYCHIC_TERRAIN_BLASTOISE.md): 필수 전개파티 02 — 에써르·거북왕 사이코필드 및 혼합군
- [`docs/archetypes/RAIN_TEAM.md`](docs/archetypes/RAIN_TEAM.md): 필수 전개파티 01 — 사용자 제공 M6 비파티 코어와 변형군
- [`docs/REQUIRED_SETUP_MATCHUPS.md`](docs/REQUIRED_SETUP_MATCHUPS.md): 출현 빈도와 무관하게 반드시 압도해야 할 정형 전개파티 검증
- [`docs/SET_VARIANT_ANALYSIS.md`](docs/SET_VARIANT_ANALYSIS.md): 상대 기술·도구·수치 변형의 영향도와 기회비용 분석
- [`docs/MATCHUP_AUDIT_PROTOCOL.md`](docs/MATCHUP_AUDIT_PROTOCOL.md): 모든 주요 상대 파티에 적용할 선출·승리 플랜 검증 절차
- [`docs/MATCHUP_REGISTRY.md`](docs/MATCHUP_REGISTRY.md): 사용자 제공 예정인 파티 목록의 검토 현황
- [`docs/VALIDATION_FRAMEWORK.md`](docs/VALIDATION_FRAMEWORK.md): 기존 랭커 파티 대비 우월성 검증 프레임워크 (AI 제안/검토 전)
- [`docs/DECISION_LOG.md`](docs/DECISION_LOG.md): 피드백·합의·보류 사항과 판단 이유
- [`docs/RECORDING_POLICY.md`](docs/RECORDING_POLICY.md): 대화 원문 보존과 문서 개정 방법
- [`conversations/`](conversations/): 날짜·주제별 대화 원문 아카이브 (과거 기록 보존)
- [`conversations/2026-10-28-initial-discussion.md`](conversations/2026-10-28-initial-discussion.md): 2026-10-28 최초 대화 기록
- [`CHANGELOG.md`](CHANGELOG.md): 문서 버전과 변경 이력

## 운영 원칙

1. **conversations는 원문, docs는 사고방식의 현재 버전.** 두 계층을 분리한다.
2. 사용자와 어시스턴트의 실제 논의 흐름, 반론, 수정 이유를 가능한 한 원문 그대로 보존한다.
3. 사용자가 승인한 방향과 AI가 일방적으로 제안한 가설을 구별한다.
4. 피드백이 생기면 핵심 원칙을 검토하고, 변경 이유를 `DECISION_LOG.md`에 기록한다.
5. 기존 대화 기록은 소급해 수정하지 않는다. 현재 기준과 과거 대화가 달라질 수 있다.
6. 특정 포켓몬이나 메타의 사례를 일반 법칙으로 과도하게 확장하지 않는다.
7. 원칙은 실제 파티 검증과 사용자 피드백을 통해 개정되는 작업 기준이다.

**중요:** GitHub 쓰기 작업을 실제 수행해야 저장된다. 메시지마다 자동으로 백업하거나 채팅 종료 후 백그라운드에서 기록하는 기능은 현재 구성되어 있지 않다.

초기 작성일: **2026-10-28** (KST)
