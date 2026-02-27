# pdf-ux Plan

## 1. Feature Overview

**Feature Name**: pdf-ux
**Created**: 2026-02-28
**Priority**: High
**Estimated Scope**: Small (3 files)

### 1.1 Summary

견적서(Quotation) / 발주서(Purchase Order) PDF 디자인 개선 —
현재 기본 스타일의 PDF를 회사 브랜딩이 적용된 전문적인 상용 문서로 업그레이드한다.
레이아웃, 컬러 팔레트, 타이포그래피, 서명란, 약관 섹션을 포함한 완성도 높은 문서를 제공한다.

### 1.2 Current State (실측)

**`app/views/layouts/pdf.html.erb`**:
- 기본 CSS만 존재 (Primary color #1E3A5F, 간단한 table/grid)
- 헤더: 텍스트만 (로고 없음)
- 푸터: 단순 텍스트 1줄
- 페이지 패딩: `24mm 20mm`

**`app/views/orders/pdf/quote.html.erb`** (76줄):
- 발주처 정보 grid (2-col)
- 품목 테이블 (단일 행)
- 결제 조건 텍스트
- 서명란 없음

**`app/views/orders/pdf/purchase_order.html.erb`** (95줄):
- 공급사 정보 grid
- 발주 품목 테이블 (selected_quote 반영)
- 배송 조건 grid
- 서명란 3칸 (담당자/확인/승인) — 기본 border-top 스타일

**문제점**:
1. **회사 로고 없음**: 헤더에 텍스트만 — 비전문적
2. **컬러 액센트 부족**: 브랜드 컬러 활용 미흡
3. **서명란 빈약**: 견적서에 서명란 없음, 발주서도 최소
4. **약관/안내 섹션 없음**: 실제 비즈니스 문서에 필요한 Terms 미포함
5. **헤더/푸터 단조로움**: 문서 번호·날짜·페이지 정보 강조 부족
6. **견적서에 유효기간 강조 없음**: 중요 정보가 일반 텍스트와 동일

---

## 2. Goals

| FR | 목표 |
|----|------|
| FR-01 | **레이아웃 레이아웃 pdf.html.erb 개선**: 헤더 브랜드 바, 구분선, 푸터 강화 |
| FR-02 | **견적서 quote.html.erb 개선**: 유효기간 강조 박스, 서명란 추가, Terms 섹션 |
| FR-03 | **발주서 purchase_order.html.erb 개선**: 공급사 정보 강화, 서명란 개선, Terms 섹션 |

### Out of Scope
- 실제 이미지 로고 파일 삽입 (텍스트 로고로 대체)
- 다국어 PDF (별도 기능)
- 전자서명 연동

---

## 3. Technical Approach

### 3.1 Files to Modify

| File | Change |
|------|--------|
| `app/views/layouts/pdf.html.erb` | 헤더 브랜드 바 + CSS 강화 + 푸터 개선 |
| `app/views/orders/pdf/quote.html.erb` | 유효기간 강조 + 서명란 + Terms |
| `app/views/orders/pdf/purchase_order.html.erb` | 공급사 상세 + 서명란 개선 + Terms |

### 3.2 레이아웃 개선 방향

```
┌────────────────────────────────────────┐
│ ■ AtoZ2010 Inc.    [QUOTATION / P.O.] │  ← 브랜드 헤더 바 (navy bg)
├────────────────────────────────────────┤
│  문서 제목 + 번호                        │
│  [발주처/공급사 정보 grid]               │
│  [품목 테이블]                          │
│  [금액 합계]                            │
│  [Terms & Conditions]                  │
│  [서명란]                               │
├────────────────────────────────────────┤
│  AtoZ2010 Inc. · Page 1 · 날짜         │  ← 강화된 푸터
└────────────────────────────────────────┘
```

### 3.3 견적서 유효기간 강조 박스

```html
<div class="validity-box">
  <span>견적 유효기간</span>
  <strong>2026-03-30까지 (30일)</strong>
</div>
```

### 3.4 서명란 개선 (공통)

```
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│              │  │              │  │              │
│   담당자      │  │    확인       │  │    승인       │
│  (날짜: ___)  │  │  (날짜: ___)  │  │  (날짜: ___)  │
└──────────────┘  └──────────────┘  └──────────────┘
```

### 3.5 Terms & Conditions 섹션

견적서/발주서 하단 공통:
- 결제 조건, 납기 조건, 유효 기간, 분쟁 해결 조항 (영문)

---

## 4. Completion Criteria

| # | Criteria |
|---|----------|
| 1 | PDF 레이아웃에 네이비 브랜드 헤더 바 표시 |
| 2 | 견적서 유효기간 강조 박스 표시 |
| 3 | 견적서에 서명란 (담당자/확인/승인) 추가 |
| 4 | 발주서 서명란 날짜란 포함으로 개선 |
| 5 | 견적서/발주서 모두 Terms & Conditions 섹션 포함 |
| 6 | 푸터에 문서번호 + 페이지 정보 강화 |
| 7 | Gap Analysis Match Rate >= 90% |

---

## 5. Dependencies

- `wicked_pdf` gem — 기존 존재
- `app/views/layouts/pdf.html.erb` — 기존 존재
- `@order.order_quotes.find_by(selected: true)` — 기존 존재

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
