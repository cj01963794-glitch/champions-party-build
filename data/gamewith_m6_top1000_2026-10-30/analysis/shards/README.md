# 분할 CSV 조회

GitHub에서 조회하기 편하도록 상위 analysis 디렉터리의 대용량 조건부 통계 및 조합 유사성 CSV를 용량별로 분할했다.

- `conditional_pairs_XX.csv`: 2마리 앵커의 조건부 채용 통계
- `conditional_triples_XX.csv`: 3마리 앵커의 조건부 채용 통계
- `triple_neighbors_by_shared_pair_XX.csv`: 공통 두 포켓몬을 가진 3마리 조합의 역인덱스
- 각 파일별 manifest에는 원본 데이터의 1부터 시작하는 행 범위를 기록했다.
- 분할 CSV는 헤더를 각자 가진다. 파일 번호순으로 이어 붙이면서 첫 파일을 제외한 헤더를 지우면 상위의 원본 CSV가 된다.
- 재계산은 상위 폴더의 `build_database.py`를 사용한다.
