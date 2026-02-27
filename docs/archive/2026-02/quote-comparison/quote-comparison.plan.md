# Plan: quote-comparison
> 견적 비교 기능 강화 — 다중 견적 입력 → 비교 테이블 → 선택 → PDF 발주서 자동연동

**Feature**: quote-comparison
**Phase**: Plan
**Started**: 2026-02-28
**Priority**: High

---

## 배경 및 목적

AtoZ2010은 구매 오더마다 복수의 거래처에서 견적을 받아 비교한 뒤 발주처를 결정한다.
현재는 OrderQuote 모델/컨트롤러만 있고 **뷰가 전혀 없어** 사이드바 단순 리스트만 존재한다.

- `order_quotes/new` 폼 없음 → 견적 추가 링크 클릭 시 404
- 비교 테이블 없음 → 단가·리드타임·유효기간을 한눈에 볼 수 없음
- 수량×단가 총액 계산 없음 → 구매 의사결정에 수작업 필요
- 인라인 추가 UI 없음 → 페이지 이동 불편

---

## 기능 요구사항 (FR)

### FR-01: 견적 추가 폼 (order_quotes/new)
- 거래처 select, 단가, 통화(USD/KRW/AED/EUR), 납기일수, 유효기간, 메모 입력
- Order 상세 페이지에서 Turbo Frame으로 인라인 슬라이드 폼 표시 (페이지 이동 없음)
- 저장 성공 시 사이드바 견적 목록 자동 갱신

### FR-02: 견적 비교 테이블
- 오더 상세 사이드바 → 가로 비교 테이블 (거래처별 열)
- 표시 항목: 거래처명, 단가, 총액(단가×수량), 통화, 납기일수, 유효기간, 메모
- 가장 낮은 단가 행 하이라이트 (시각적 강조)
- 선택된 견적 배지 표시

### FR-03: 수량×단가 총액 자동 계산
- Order.quantity 컬럼 활용 → 각 견적의 총액(unit_price × quantity) 실시간 표시
- 총액 기준 정렬 옵션

### FR-04: 견적 선택 → 발주서 PDF 자동연동
- 선택 버튼 1클릭 → selected: true 업데이트 (이미 구현됨)
- 선택 견적의 거래처가 order.supplier_id에 자동 반영
- PDF 발주서(`orders/pdf/purchase_order`)에 선택 견적 정보 표시 (이미 연동됨)

---

## 현재 구현 상태 (코드 실측)

| 항목 | 상태 | 비고 |
|------|:----:|------|
| OrderQuote 모델 | ✅ | unit_price, currency, lead_time_days, validity_date, notes, selected |
| OrderQuotesController | ✅ | new/create/destroy/select 4개 액션 |
| order_quotes/new 뷰 | ❌ | 파일 없음 → 404 |
| 사이드바 리스트 | ✅ | 단순 리스트 (거래처+가격만) |
| 비교 테이블 UI | ❌ | 없음 |
| 총액 계산 | ❌ | 없음 |
| PDF 발주서 연동 | ✅ | selected_quote 참조 |

---

## 구현 범위

| FR | 구현 필요 파일 | 난이도 |
|----|--------------|:------:|
| FR-01 | `app/views/order_quotes/new.html.erb` + `_form.html.erb` | 하 |
| FR-02 | `app/views/orders/_sidebar_panel.html.erb` 견적 섹션 교체 | 중 |
| FR-03 | `_sidebar_panel.html.erb` 내 총액 계산 로직 | 하 |
| FR-04 | `order_quotes_controller.rb` select 액션 → supplier_id 업데이트 | 하 |

---

## 비즈니스 영향

- 견적 비교 의사결정 시간: 5분 → 30초
- 견적 추가 불가 버그(404) 해소
- 발주처 자동 업데이트로 데이터 정합성 확보
