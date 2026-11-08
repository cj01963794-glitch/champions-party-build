# GameWith Pokémon Champions 파티 수집기

포켓몬 챔피언스의 GameWith 파티 공개 페이지에 표시된 내용을 사용자의 Chrome 브라우저에서 수집하는 도구입니다. M6와 M7 수집에 사용한 코드 원본을 보존합니다.

## 파일

- `gamewith_browser_collector_v2.js`: Chrome 개발자 도구 콘솔에서 실행하는 브라우저 DOM 수집기. 메가 폼 탭(`_form-tabs`)이 있는 포켓몬의 **일반 폼** 상세정보를 읽도록 수정한 v2입니다.
- `gamewith_colab_converter.ipynb`: 다운로드한 JSON을 포켓몬 단위 CSV로 변환하는 Google Colab 노트북입니다.

## 사용 방법

1. [GameWith 파티 페이지](https://gamewith.jp/pokemon-champions/560474)를 Chrome에서 열고 수집할 시즌(M6 또는 M7)을 선택합니다.
2. 파티 목록이 정상 표시되면 F12 → 콘솔에 `gamewith_browser_collector_v2.js` 전체 내용을 붙여 넣고 실행합니다. 서로 다른 시즌을 동시에 수집하지 마세요.
3. 콘솔의 페이지 진행 상태를 확인합니다. 정상 완료 또는 종료 시 `GameWith_파티_전체데이터.json`을 저장합니다.
4. 필요하다면 `gamewith_colab_converter.ipynb`을 사용해 CSV로 변환합니다.

### 중단과 복구

- 실행 중 수집 데이터는 `window.__gamewithData`에 보관됩니다.
- 중단 요청: `window.__gamewithStop = true`. 현재 작업이 종료되면 JSON이 다운로드됩니다.
- 새로고침/탭 닫기는 즉시 중단하지만 아직 다운로드하지 않은 결과가 손실될 수 있습니다.
- 콘솔의 결과 JSON `status`가 `NO_IDENTIFIABLE_NEXT_BUTTON__LAST_PAGE_UNVERIFIED`라면 **마지막 페이지 도달을 확인한 것이 아닙니다.** 페이지 누락 여부를 별도로 검증해야 합니다.

## 수집 데이터 및 한계

파티마다 시즌·등수·작성자·포켓몬 6마리와, 공개된 상세 패널의 도구·특성·기술·성격·HABCDS 투자 포인트를 추출합니다. 구조에 따라 메가 폼 선택 탭이 있으면 일반 폼만 읽습니다. 파티 목록 UI가 바뀌거나 상세 패널이 비공개인 경우 데이터가 누락될 수 있습니다.

자동 수집 성공 여부는 세팅 완성 여부와 다릅니다. 예를 들어 성격 또는 투자 포인트가 사이트에서 `불명`으로 표시되거나, 일부 기술이 누락될 수 있습니다. 수집 JSON의 `error`와 `status`, 각 상세 필드를 함께 확인하세요.

GameWith 사이트의 이용 약관 및 공개 범위를 존중하며, 접속 제한/로그인/접근 제어를 우회하지 않습니다.

> 2026-11: 사용자 제공 DOM 구조에 기반하여 수집한 실제 M6·M7 데이터는 별도 한국어 번역·수동 교정 작업을 거쳤습니다. 이 폴더는 수집기와 변환기의 **원본 코드 보관** 용도입니다.
