# 올라라! 포켓몬 타워! — AI 코드 스냅샷

이 폴더는 포켓몬 챔피언스 싱글 3v3 팀 구축 연구를 위한 **외부 게임 AI 연구 자료**입니다.

## 원본 및 범위

- 자료 출처: 사용자가 제공한 `올라라! 포켓몬 타워!_v2_1003.zip`에서 정적으로 추출
- 추출 위치: `Data/PluginScripts.rxdata` 안의 `Battle AI Improved`와 `Data/Scripts/011_Battle/005_AI` 등
- `improved_ai/`: 배틀 AI 개선 플러그인 원본 Ruby 소스 22개
- `essentials_base_ai/`: 기반 Pokémon Essentials 배틀 AI Ruby 소스 11개
- `compatibility_ai/`: 세대/배틀 기능 플러그인의 AI 관련 보완 코드 14개
- `ai_improved_exact_snapshot.tar.bz2`: **사용자 업로드본에서 추출한 개선 AI 22개를 원문 그대로 보존한 압축본**
- `MANIFEST.tsv`: 원본 경로, 저장 경로, SHA-256, 바이트 크기
- `ANALYSIS.md`: 정적 분석 요약

## 조사 시 유의사항

1. 이 소스는 **올포타 확장팩 v2_1003 스냅샷**입니다. 2026년 11월 공개된 `pokemon-tower-battle.rotatedtriangle.chatgpt.site`의 실제 웹 코드를 확보했다는 뜻은 아닙니다.
2. `simulate_battle(max_turns=10)`은 주로 현재 대면 기술 수순을 평가하는 코드로, 3대3 파티 전체의 장기 사이클을 전수 탐색한다는 증거가 아닙니다.
3. 업데이터 두 개(`pokemon_tower_updater.apk`, `pokemon_tower_updater_windows.zip`)는 별도 업데이터이며 AI 판단 로직의 주된 출처가 아닙니다.
4. 코드 해석은 정적 분석입니다. 실제 게임 룰과의 일치 여부, 모든 코드 경로의 실행 여부를 검증하지 않았습니다.
5. 타인의 개발 결과물을 연구 목적으로 보관한 것입니다. **원저작자의 권리를 인정하며 재배포/변경에 대한 라이선스가 확인되었다는 뜻이 아닙니다.**
6. 관련 공개 저장소: https://github.com/erablah/gouppokemontower-improved-battle-ai (과거 시점 코드. 업로드된 스냅샷과 일부 파일 구성 및 내용이 다름)

## 주요 코드 탐색

- `improved_ai/001_AI_Improved_Core.rb`: AI 행동 선택 절차
- `improved_ai/001b_AI_MoveSimulation.rb`: 대면 시뮬레이션
- `improved_ai/001d_AI_Improved_Matchup.rb`: 상대 행동 / 매치업 추정
- `improved_ai/004_AI_Improved_MoveEffectScore.rb`: 도발·트릭·흑안개 등 기술 평가
- `improved_ai/006_AI_Improved_ShouldSwitch.rb`: 교체 여부
- `improved_ai/007_AI_Improved_ScoreReplacement.rb`: 교체 후보 평가
- `improved_ai/001g_AI_Improved_SackReplacement.rb`: 희생 교체
- `improved_ai/009_Fog_Of_War.rb`: 상대 정보 제한

> 라이선스와 출처를 지우지 않고 분석 목적에서 취급할 것. 포챔스에 바로 이식 가능한 구현이라는 의미는 아닙니다.
