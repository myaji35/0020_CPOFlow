# CPOFlow 전체 기능 테스트 시나리오 + 구현도 평가

> 130개 엔드포인트 × 테스트 시나리오 × 기획의도 대비 구현 점수.
> 작성일: 2026-04-16 | 평가: 코드 기반 (컨트롤러+뷰+모델+테스트)
> **전체 평균: 81%**

### 점수 기준
| 점수 | 의미 |
|------|------|
| 100% | 컨트롤러+뷰+모델+테스트 완비, 실제 동작 확인 |
| 80% | 기능 동작하나 edge case 미처리 또는 테스트 부족 |
| 60% | 기본 골격 있으나 UX 미완성 또는 주요 기능 일부 누락 |
| 40% | 스켈레톤/placeholder 수준 |
| 20% | 라우트만 존재 |
| 0% | 코드 없음 |

---

## 대시보드 — 95%

> 196줄 컨트롤러, 874줄 뷰. KPI 8종+보드별 요약+스파크라인 완성. 미흡: 실시간 갱신 없음.

- [ ] **메인 뷰** `GET /dashboard` [95%] — 로그인→KPI 숫자 표시 확인→보드 2개 이상 시 보드별 카드 표시→긴급 주문 클릭→상세 이동
- [ ] **Sheets 동기화** `POST /dashboard/sync` [90%] — 동기화 버튼 클릭→"동기화 완료" 메시지→데이터 반영 확인

## 받은편지함 — 90%

> 535줄 컨트롤러, 1841줄 뷰. 18개 액션 완전 구현. Gmail 3-pane 레이아웃. 미흡: Anthropic 크레딧 소진 시 AI 기능 fallback UX.

- [ ] **목록** `GET /inbox` [95%] — 페이지 로드→이메일 30건 표시→"RFQ 대기" 탭 클릭→필터 작동→triage 건만 표시
- [ ] **상세 보기** `GET /inbox/:id` [90%] — 이메일 클릭→원문 탭 표시→번역 탭→한국어 출력→첨부 탭→PDF 파일 목록 확인
- [ ] **삭제** `DELETE /inbox/:id` [95%] — 삭제 클릭→확인→목록에서 사라짐→Gmail에서도 Trash 확인
- [ ] **칸반 투입** `POST /inbox/:id/convert` [90%] — 보드 선택→"칸반으로 이동" 클릭→칸반 New 칼럼에 카드 표시→rfq_status=triage 확인
- [ ] **Gmail 동기화** `POST /inbox/sync` [95%] — 동기화 클릭→새 메일 수신→목록 갱신
- [ ] **번역** `GET /inbox/:id/translate` [80%] — 번역 탭 클릭→한국어 텍스트 표시→원문과 의미 대응 확인. *API 크레딧 의존*
- [ ] **첨부 다운로드** `GET /inbox/:id/attachment/:key` [95%] — 다운로드 아이콘 클릭→파일 다운로드 시작→파일 열림 확인
- [ ] **첨부 미리보기** `GET /inbox/:id/attachment_preview/:blob_id` [90%] — "클릭하여 미리보기"→모달 열림→PDF 렌더링→ESC로 닫기
- [ ] **링크 AI 분석** `POST /inbox/analyze_link` [75%] — "AI 분석" 클릭→로딩→요약 텍스트 표시. *API 크레딧 의존, Ariba 링크 수집 별도*
- [ ] **RFQ 피드백** `POST /inbox/:id/feedback` [90%] — "RFQ 아님" 클릭→상태 변경→다음 동일 패턴 판정 개선 확인
- [ ] **답변 초안 생성** `POST /inbox/:id/generate_reply` [70%] — "답변 초안" 탭→생성 클릭→로딩→초안 표시. *API 크레딧 소진 시 실패, fallback 없음*
- [ ] **일괄 삭제** `POST /inbox/bulk_delete` [95%] — 3건 체크→"삭제" 클릭→3건 사라짐
- [ ] **일괄 Trash** `POST /inbox/bulk_trash` [95%] — 체크 선택→Trash→Gmail에서 확인
- [ ] **일괄 칸반 투입** `POST /inbox/bulk_to_kanban` [85%] — 5건 체크→보드 선택→투입→칸반에 5건 표시
- [ ] **일괄 복원** `POST /inbox/bulk_restore` [90%] — 삭제된 건 선택→복원→목록에 다시 표시

## 칸반 — 85%

> 233줄 컨트롤러, 911줄 뷰. 복수 보드+성능 최적화(lazy load). 미흡: 커스텀 보드 카드 이동 후 UI 즉시 반영 미세 지연.

- [ ] **보드 뷰** `GET /kanban` [90%] — 구매보드→9칼럼 표시→인사보드 전환→커스텀 칼럼 표시→담당자 필터→해당 건만 표시
- [ ] **카드 이동** `PATCH /orders/:id/move` [85%] — 카드 드래그→다음 칼럼 드롭→칼럼 카운트 변경→Activity 기록 확인
- [ ] **카드 병합** `POST /kanban/merge` [80%] — 병합 모드→중복 그룹 선택→병합→1건으로 통합→서브오더 유지
- [ ] **카드 분리** `PATCH /kanban/split/:id` [80%] — 카드 메뉴→분리→독립 카드로 복원

## 발주 목록 — 80%

> 500줄 컨트롤러. CRUD+PDF+첨부+태스크+코멘트+담당자+견적비교+플로우+OrderLinks 완성. 미흡: index 뷰 17K줄 과대, UX 최적화 여지.

- [ ] **목록** `GET /orders` [85%] — 목록→거래처 필터→기간 필터→결과 건수 표시→페이지네이션
- [ ] **신규 등록 (구매)** `GET/POST /orders/new` [85%] — 구매보드: 제목+고객사+거래처+품목 입력→등록→칸반 New에 표시
- [ ] **신규 등록 (커스텀)** `GET/POST /orders/new` [80%] — 커스텀보드: 제목+@담당자+파일첨부→카드 등록→칸반에 표시
- [ ] **상세** `GET /orders/:id` [85%] — 펼침 화면 클릭→전체 페이지 로드→6탭 모두 접근 가능
- [ ] **수정** `PATCH /orders/:id` [85%] — 제목 수정→저장→칸반 카드 제목 변경 확인
- [ ] **삭제** `DELETE /orders/:id` [90%] — 삭제→칸반에서 사라짐→목록에서 제거
- [ ] **상태 변경** `PATCH /orders/:id/move_status` [85%] — 다음 단계 버튼→상태 변경→Activity 기록
- [ ] **빠른 수정** `PATCH /orders/:id/quick_update` [80%] — 관리번호 클릭→인라인 입력→Enter→저장 확인
- [ ] **파일 첨부** `POST /orders/:id/attach` [90%] — 파일 선택→업로드→첨부 목록에 표시→미리보기 클릭→표시
- [ ] **URL 첨부** `POST /orders/:id/attach_from_url` [80%] — URL 입력→다운로드→첨부 추가. Google Drive 폴더→전체 다운로드. 비공개→에러 메시지
- [ ] **파일 삭제** `DELETE /orders/:id/detach/:blob_id` [90%] — 삭제 아이콘→확인→목록에서 제거→카운트 감소
- [ ] **견적서 PDF** `GET /orders/:id/pdf/quote` [75%] — PDF 클릭→새 탭→PDF 렌더→회사명/품목/금액 포함. *레이아웃 기본 수준*
- [ ] **발주서 PDF** `GET /orders/:id/pdf/purchase_order` [75%] — PDF 클릭→PO 양식→PO번호/거래처/품목 포함. *레이아웃 기본 수준*
- [ ] **첨부 미리보기** `GET /orders/:id/attachment_preview/:blob_id` [90%] — 미리보기 클릭→전역 모달→PDF 표시→닫기→드로어 유지
- [ ] **Ref 미리보기** `GET /orders/preview_by_ref` [70%] — 칸반 카드 hover→팝업→관련 건 수 + 제목 표시. *hover 딜레이 조정 필요*
- [ ] **일괄 처리** `POST /orders/bulk` [75%] — 선택모드→3건 체크→이동→모달→상태 선택→일괄 변경
- [ ] **CSV 내보내기** `GET /orders/bulk/export_csv` [80%] — CSV 내보내기 클릭→파일 다운로드→Excel에서 열림→컬럼 확인

### 태스크 — 85%

- [ ] **추가** `POST /orders/:id/tasks` [85%] — 입력란에 "회의 준비 @KANG"→추가→태스크 목록에 표시→담당자 아이콘
- [ ] **수정** `PATCH /orders/:id/tasks/:id` [85%] — 체크박스 클릭→완료 표시→Tasks 0/1→1/1 변경
- [ ] **삭제** `DELETE /orders/:id/tasks/:id` [90%] — 삭제→목록에서 제거→카운트 감소

### 코멘트 — 90%

- [ ] **추가** `POST /orders/:id/comments` [90%] — 텍스트 입력→추가→타임스탬프+작성자 표시
- [ ] **삭제** `DELETE /orders/:id/comments/:id` [90%] — 삭제 클릭→코멘트 사라짐

### 담당자 — 85%

- [ ] **배정** `POST /orders/:id/assignments` [85%] — 담당자 추가→직원 선택→아바타 표시→칸반 카드에도 표시
- [ ] **해제** `DELETE /orders/:id/assignments/:id` [85%] — X 클릭→아바타 제거

### 견적 비교 — 75%

- [ ] **추가** `POST /orders/:id/order_quotes` [75%] — 새 견적→거래처+금액 입력→목록에 추가
- [ ] **선택** `PATCH /orders/:id/order_quotes/:id/select` [70%] — 선택 버튼→해당 견적 강조→나머지 비활성화. *비교 UI 기본 수준*
- [ ] **삭제** `DELETE /orders/:id/order_quotes/:id` [80%] — 삭제→목록에서 제거

### 플로우 — 70%

- [ ] **조회** `GET /orders/:id/flow` [70%] — 플로우 탭→타임라인 표시→각 단계 날짜/담당자 확인. *시각화 기본 수준, 인터랙션 없음*

### OrderLinks — 70%

- [ ] **생성** `POST /order_links` [70%] — 연결 추가→대상 검색→선택→연결 표시
- [ ] **확인** `PATCH /order_links/:id/confirm` [70%] — 확인→연결 확정
- [ ] **거절** `PATCH /order_links/:id/reject` [70%] — 거절→연결 해제
- [ ] **검색** `GET /order_links/search` [75%] — 키워드 입력→후보 목록→선택

## 일정 — 75%

> 21줄 컨트롤러. 기본 월간 뷰+통계. 미흡: 주간/일간 뷰 없음, 드래그로 due_date 변경 불가.

- [ ] **캘린더** `GET /calendar` [75%] — 캘린더 로드→이번 달 납기 건 표시→날짜 클릭→해당 주문 표시→이전/다음 월 이동

## 팀 — 80%

> 52줄 컨트롤러. 워크로드 통계 포함. 미흡: 팀 성과 시각화, 협업 채널 없음.

- [ ] **목록** `GET /team` [85%] — 목록→8명 표시→역할 배지 확인
- [ ] **상세** `GET /team/:id` [80%] — 이름 클릭→프로필→담당 주문 목록
- [ ] **역할 변경** `PATCH /team/:id/update_role` [75%] — admin으로 변경→저장→해당 유저 로그인→admin 메뉴 접근 가능 확인

## 발주처 — 85%

> CRUD 완성+거래이력 탭+통계 카드+담당자 중첩. 미흡: 리스크 등급 자동 계산 정확도.

- [ ] **목록** `GET /clients` [85%] — 목록→검색→결과 표시
- [ ] **생성** `POST /clients` [85%] — 신규→이름/국가 입력→저장→목록 표시
- [ ] **상세** `GET /clients/:id` [85%] — 상세→거래 이력 확인
- [ ] **수정** `PATCH /clients/:id` [85%] — 수정→저장→변경 반영
- [ ] **삭제** `DELETE /clients/:id` [80%] — 삭제→목록에서 제거. *발주 이력 있으면 soft delete 미적용*
- [ ] **검색 API** `GET /clients/search` [90%] — Order 폼→발주처 필드 타이핑→드롭다운→선택→hidden_id 설정
- [ ] **담당자 추가** `POST /clients/:id/contact_persons` [85%] — 추가→이름/이메일/전화→저장→WhatsApp 링크 클릭→앱 열림
- [ ] **담당자 수정** `PATCH /clients/:id/contact_persons/:id` [85%] — 수정→저장→반영
- [ ] **담당자 삭제** `DELETE /clients/:id/contact_persons/:id` [85%] — 삭제→제거

## 거래처 — 85%

> CRUD 완성+eCount 코드 연동+품목 매핑. 미흡: eCount API 거래처 동기화 미작동.

- [ ] **목록** `GET /suppliers` [85%] — 목록→검색→결과 표시
- [ ] **생성** `POST /suppliers` [85%] — 신규→이름/eCount코드→저장→목록
- [ ] **상세** `GET /suppliers/:id` [85%] — 상세→품목 매핑 확인
- [ ] **수정** `PATCH /suppliers/:id` [85%] — 수정→저장→반영
- [ ] **검색 API** `GET /suppliers/search` [90%] — 타이핑→드롭다운→선택
- [ ] **담당자 CRUD** `CRUD /suppliers/:id/contact_persons` [85%] — 추가→저장→이메일/전화 클릭→연결→수정→삭제
- [ ] **품목 매핑 추가** `POST /suppliers/:id/supplier_products` [80%] — 품목 추가→검색→선택→매핑 표시
- [ ] **품목 매핑 삭제** `DELETE /suppliers/:id/supplier_products/:id` [80%] — 삭제→매핑 해제

## 외부 담당자 — 80%

> 통합 뷰+서명 추출. 미흡: OCR/명함 스캔 미연동.

- [ ] **목록** `GET /contact_persons` [85%] — 목록→검색→이름 클릭→소속/연락처 표시
- [ ] **상세** `GET /contact_persons/:id` [80%] — 상세 페이지→소속 발주처/거래처 표시
- [ ] **서명 추출** `POST /contact_persons/create_from_signature` [70%] — 이메일 상세→서명 추출 버튼→자동 채움→저장. *정규식 기반, AI OCR 미적용*

## 현장 — 80%

> 기본 CRUD+검색. 미흡: 지도 시각화, 현장별 지출 대시보드 없음.

- [ ] **목록** `GET /projects` [85%] — 목록→검색→표시
- [ ] **생성** `POST /projects` [85%] — 신규→이름/위치→저장
- [ ] **상세** `GET /projects/:id` [80%] — 상세→연결된 주문 확인
- [ ] **수정** `PATCH /projects/:id` [85%] — 수정→저장
- [ ] **삭제** `DELETE /projects/:id` [80%] — 삭제→제거
- [ ] **검색 API** `GET /projects/search` [90%] — Order 폼에서 타이핑→드롭다운→선택

## 직원 관리 — 85%

> CRUD+비자/계약/배정/자격증 중첩. 필터+통계 카드 완성. 미흡: 비자/계약 갱신 워크플로우 자동화 없음.

- [ ] **목록** `GET /employees` [90%] — 목록→active 직원 표시→부서/직책/파견 필터
- [ ] **생성** `POST /employees` [85%] — 신규→이름/이메일/지사→저장→목록→User 연결 확인
- [ ] **상세** `GET /employees/:id` [85%] — 상세→비자/계약/배정/자격증 탭
- [ ] **수정** `PATCH /employees/:id` [85%] — 수정→저장
- [ ] **삭제** `DELETE /employees/:id` [80%] — 삭제→제거
- [ ] **비자 추가** `POST /employees/:id/visas` [85%] — 추가→비자번호/만료일→저장→만료 30일 전 알림 발생 확인
- [ ] **비자 수정/삭제** `PATCH/DELETE /employees/:id/visas/:id` [85%] — 수정→저장→삭제→제거
- [ ] **계약 CRUD** `CRUD /employees/:id/employment_contracts` [85%] — 추가→시작/종료일/급여→저장→이력 타임라인 표시
- [ ] **배정 CRUD** `CRUD /employees/:id/employee_assignments` [80%] — 추가→현장 선택→기간→저장→투입 현황 조회
- [ ] **자격증 CRUD** `CRUD /employees/:id/certifications` [80%] — 추가→자격명/만료일→저장→만료 알림
- [ ] **부서 관리** `GET/POST/DELETE /employees/departments` [85%] — 직원 폼→부서 "+추가"→이름 입력→즉시 생성→선택 가능
- [ ] **직책 관리** `GET/POST/DELETE /employees/job_titles` [85%] — 직원 폼→직책 "+추가"→이름 입력→즉시 생성

## 조직도 — 75%

> 기본 계층 CRUD. 미흡: 그래프 시각화 기본 수준, 드래그앤드롭 조직 개편 없음.

- [ ] **메인** `GET /org_chart` [75%] — 페이지 로드→트리 구조→UAE/한국 펼침→회사→부서→직원 확인
- [ ] **국가 CRUD** `CRUD /org_chart/countries` [75%] — 추가→국가명/코드→저장→트리에 표시
- [ ] **회사 CRUD** `CRUD /org_chart/companies` [75%] — 추가→회사명/국가→저장→국가 하위에 표시
- [ ] **부서 CRUD** `CRUD /org_chart/companies/:id/departments` [75%] — 추가→부서명→저장→회사 하위에 표시→직원 배정

## 경영 리포트 — 70%

> 6개 차트(Chart.js)+CSV. 미흡: 예측 분석 없음, PDF 내보내기 없음.

- [ ] **메인** `GET /reports` [70%] — 기간 선택→차트 갱신→Top5 거래처→담당자별 처리량→수치 일관성 검증
- [ ] **CSV 내보내기** `GET /reports/export_csv` [75%] — CSV 클릭→다운로드→Excel 열기→화면 수치와 CSV 수치 일치 확인

## eCount — 60%

> 품목 10,000건 동기화 성공. 미흡: 거래처 API 엔드포인트 미확보, 거래내역 Phase 2 미착수.

- [ ] **API 동기화 대시보드** `GET /admin/ecount_sync` [80%] — 페이지→세션 활성 표시→일일 사용량 %→최근 동기화 시각→이력 테이블
- [ ] **수동 실행** `POST /admin/ecount_sync/trigger` [75%] — "품목 동기화" 클릭→백그라운드 시작→이력에 running→completed→건수 표시
- [ ] **품목 목록** `GET /admin/ecount/products` [85%] — 페이지→10,000건 표시→검색 "Sika"→필터링→품목 클릭→상세
- [ ] **품목 상세** `GET /admin/ecount/products/:id` [80%] — 상세→eCount코드/품명/단가/단위 표시→뒤로가기→목록 유지
- [ ] **거래처 목록** `GET /admin/ecount/customers` [60%] — 목록→유형 필터→검색. *API 동기화 미작동, 기존 데이터만 표시*
- [ ] **거래처 상세** `GET /admin/ecount/customers/:id` [60%] — 상세→기본 정보→관련 주문. *동기화된 데이터 10건뿐*
- [ ] **거래내역** `GET /admin/ecount/transactions` [40%] — 참조번호 기반 임시 표시. *Phase 2 OAPI 미확보, placeholder 수준*
- [ ] **Import 업로드** `POST /admin/imports` [80%] — 유형 선택→파일 선택→업로드→성공 건수→에러 건수→에러 로그 다운로드
- [ ] **Import 에러 로그** `GET /admin/imports/:id/download_errors` [70%] — 에러 로그 클릭→JSON 다운로드→실패 사유 확인
- [ ] **중복 주문** `GET/POST /admin/duplicate_orders` [75%] — 목록→중복 그룹 표시→선택→병합→1건으로 통합
- [ ] **RFQ 통계** `GET /admin/rfq_stats` [65%] — 페이지→비율 표시. *피드백 반영 추이 그래프 기본 수준*

## 메뉴 권한 — 85%

- [ ] **조회/저장** `GET/PATCH /settings/menu_permissions` [85%] — 매트릭스→viewer의 kanban read ON→저장→viewer 로그인→칸반 접근 가능→orders create OFF→신규 버튼 미표시

## 설정 — 85%

> Gmail/프로필/알림/API키/보드/블럭/카드상태 완성. 미흡: 감사 로그, 데이터 백업 UI 없음.

- [ ] **Gmail 연동** `CRUD /settings/email_accounts` [90%] — Connect→OAuth 팝업→인증→계정 표시→동기화→연결 해제→재연결
- [ ] **프로필** `PATCH /settings/profile` [85%] — 이름 변경→저장→헤더에 반영→비밀번호 변경→재로그인
- [ ] **로케일** `PATCH /settings/locale` [85%] — 영어 전환→메뉴 영어 표시→한국어 복귀→메뉴 한국어
- [ ] **테마** `PATCH /settings/theme` [85%] — 다크 모드→전체 UI 다크→라이트→복귀
- [ ] **알림 설정** `PATCH /settings/notifications` [80%] — "납기 위험" ON→테스트 발송→알림 수신 확인→OFF→미수신 확인
- [ ] **알림 테스트** `POST /settings/notifications/test` [80%] — 테스트 버튼→알림 수신→내용 확인
- [ ] **Agent 신뢰** `PATCH /settings/agent_trust/:type` [75%] — 토글 ON→자동 인사이트 표시→OFF→미표시
- [ ] **API 키 저장** `PATCH /settings/api_keys` [85%] — 키 입력→저장→"설정됨" 표시
- [ ] **API 키 검증** `POST /settings/api_keys/verify` [80%] — 검증→"유효" 표시→잘못된 키→"무효" 에러
- [ ] **보드 생성** `POST /settings/kanban_boards` [85%] — 이름/유형/팔레트→저장→기본 블럭 3개 생성→블럭 편집 이동
- [ ] **보드 수정** `PATCH /settings/kanban_boards/:id` [85%] — 수정→저장→반영
- [ ] **보드 삭제** `DELETE /settings/kanban_boards/:id` [85%] — 삭제→기본 보드는 삭제 불가 확인→활성 주문 있으면 불가
- [ ] **보드 복제** `POST /settings/kanban_boards/:id/duplicate` [80%] — 복제→(복사) 이름→칼럼도 함께 복제
- [ ] **보드 정렬** `PATCH /settings/kanban_boards/:id/reorder` [80%] — 드래그→순서 변경→칸반 콤보박스 순서 반영
- [ ] **블럭 추가** `POST /settings/kanban_columns` [85%] — 이름/색상→저장→칸반에 칼럼 표시
- [ ] **블럭 수정** `PATCH /settings/kanban_columns/:id` [85%] — 이름/색상 변경→저장→반영
- [ ] **블럭 삭제** `DELETE /settings/kanban_columns/:id` [80%] — 삭제→카드 있으면 불가 확인→빈 칼럼만 삭제
- [ ] **블럭 정렬** `PATCH /settings/kanban_columns/reorder` [80%] — 드래그→순서 변경→칸반 칼럼 순서 반영
- [ ] **카드 상태 추가** `POST /settings/card_statuses` [85%] — 이름 입력→저장→key 자동 생성→목록에 표시
- [ ] **카드 상태 수정** `POST /settings/card_statuses` (editing_id) [85%] — 편집→프리셋 색상→미리보기 변경→저장→반영
- [ ] **카드 상태 삭제** `DELETE /settings/card_statuses/:id` [85%] — 삭제→시스템 상태 불가→사용 중 불가→빈 상태만 삭제
- [ ] **카드 상태 이름 변경** `PATCH /settings/card_statuses/:id/inline_rename` [90%] — 이름 클릭→인라인 수정→Enter→즉시 반영
- [ ] **카드 상태 정렬** `PATCH /settings/card_statuses/reorder` [85%] — 드래그→순서 변경
- [ ] **테마 일괄 적용** `POST /settings/card_statuses/apply_theme` [90%] — Pastel 클릭→7개 상태 색상 일괄 변경→미리보기 확인

## 공통 — 80%

> 검색/멘션/알림/AI인사이트/OAuth 완성. 미흡: 실시간 검색 제안, 알림 다중화(이메일/푸시).

- [ ] **글로벌 검색** `GET /search` [80%] — ⌘K→검색창→"Nawah" 입력→주문/거래처/직원 결과→클릭→해당 페이지 이동
- [ ] **@멘션** `GET /users/mention_suggestions` [85%] — @KA 입력→KANG 표시→선택→hidden_id 설정→폼 제출→담당자 배정
- [ ] **알림 목록** `GET /notifications` [80%] — 벨 아이콘→미읽음 건 표시→클릭→읽음 처리
- [ ] **알림 전체 읽음** `PATCH /notifications/read_all` [85%] — 전체 읽음→배지 사라짐
- [ ] **AI 인사이트 무시** `PATCH /agent_insights/:id/dismiss` [80%] — "무시"→배너 숨김
- [ ] **AI 인사이트 피드백** `PATCH /agent_insights/:id/feedback` [75%] — "유용" 클릭→피드백 기록
- [ ] **Gmail OAuth 인증** `GET /gmail/oauth/authorize` [90%] — 인증 시작→Google 팝업→권한 허용
- [ ] **Gmail OAuth 콜백** `GET /gmail/oauth/callback` [90%] — 콜백→토큰 저장→이메일 동기화 시작
- [ ] **Gmail OAuth 해제** `DELETE /gmail/oauth/disconnect/:id` [90%] — 연결 해제→계정 제거

---

## 종합 점수

| 메뉴 | 점수 | 핵심 미흡사항 |
|------|------|-------------|
| 대시보드 | **95%** | 실시간 갱신 없음 |
| 받은편지함 | **90%** | API 크레딧 소진 시 AI fallback UX |
| 칸반 | **85%** | 커스텀 보드 이동 후 UI 미세 지연 |
| 발주 목록 | **80%** | index 뷰 과대, PDF 레이아웃 기본 |
| 일정 | **75%** | 주간/일간 뷰 없음, 드래그 미지원 |
| 팀 | **80%** | 성과 시각화 없음 |
| 발주처 | **85%** | 리스크 자동 계산 정확도 |
| 거래처 | **85%** | eCount API 동기화 미작동 |
| 외부 담당자 | **80%** | AI OCR 미적용 |
| 현장 | **80%** | 지도 시각화 없음 |
| 직원 관리 | **85%** | 갱신 워크플로우 자동화 없음 |
| 조직도 | **75%** | 시각화 기본 수준 |
| 경영 리포트 | **70%** | 예측 분석/PDF 없음 |
| eCount | **60%** | 거래처/거래내역 Phase 2 미착수 |
| 설정 | **85%** | 감사 로그 없음 |
| 공통 | **80%** | 실시간 검색/알림 다중화 없음 |
| **전체 평균** | **81%** | |

**총 130개 시나리오** | 평가일: 2026-04-16 | CPOFlow (AtoZ2010 Inc.)
