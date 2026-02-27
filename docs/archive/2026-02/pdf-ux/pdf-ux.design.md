# pdf-ux Design

## 1. Overview

**Feature**: pdf-ux (견적서/발주서 PDF 디자인 개선)
**Design Date**: 2026-02-28
**Plan Reference**: `docs/01-plan/features/pdf-ux.plan.md`
**Implementation Target**:
- `app/views/layouts/pdf.html.erb`
- `app/views/orders/pdf/quote.html.erb`
- `app/views/orders/pdf/purchase_order.html.erb`

---

## 2. Current State Analysis

### 2.1 pdf.html.erb (현재)
- CSS: body, h1/h2, table, header-row, info-grid, badge, footer 기본 정의
- 헤더: `<div class="header-row">` — 좌측 제목 / 우측 회사명 텍스트
- 푸터: `position:fixed; bottom:10mm` 단순 1줄 텍스트

### 2.2 quote.html.erb (현재, 76줄)
- header-row → info-grid(2col) → table → 결제조건 텍스트
- 서명란 없음, 유효기간 일반 텍스트로만 표시

### 2.3 purchase_order.html.erb (현재, 95줄)
- header-row → info-grid(2col) → table → 배송조건 grid
- 서명란: `border-top` 단순 라인 3개 (날짜란 없음)

---

## 3. Functional Requirements Design

### FR-01: pdf.html.erb — 레이아웃 CSS 강화

#### 3.1 추가 CSS 클래스

```css
/* 브랜드 헤더 바 */
.brand-bar {
  background: #1E3A5F;
  color: white;
  padding: 10px 20mm;
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin: -24mm -20mm 20px;  /* page padding 상쇄 후 full-width */
}
.brand-bar .brand-name {
  font-size: 14pt;
  font-weight: bold;
  letter-spacing: 0.5px;
}
.brand-bar .brand-sub {
  font-size: 8pt;
  opacity: 0.8;
  margin-top: 2px;
}
.brand-bar .doc-type {
  font-size: 11pt;
  font-weight: bold;
  letter-spacing: 2px;
  opacity: 0.9;
}

/* 문서 번호 + 날짜 헤더 */
.doc-meta {
  display: flex;
  justify-content: space-between;
  align-items: flex-end;
  margin-bottom: 20px;
  padding-bottom: 12px;
  border-bottom: 3px solid #1E3A5F;
}
.doc-title {
  font-size: 22pt;
  font-weight: bold;
  color: #1E3A5F;
}
.doc-number {
  font-size: 9pt;
  color: #6b7280;
  margin-top: 4px;
}
.doc-date-block {
  text-align: right;
  font-size: 9pt;
  color: #6b7280;
  line-height: 1.8;
}

/* 유효기간/강조 박스 */
.highlight-box {
  background: #eff6ff;
  border: 1.5px solid #1E3A5F;
  border-radius: 4px;
  padding: 8px 14px;
  display: inline-flex;
  align-items: center;
  gap: 12px;
  margin: 8px 0 16px;
  font-size: 10pt;
}
.highlight-box .hl-label {
  color: #6b7280;
  font-size: 8pt;
}
.highlight-box .hl-value {
  color: #1E3A5F;
  font-weight: bold;
  font-size: 11pt;
}

/* 섹션 헤더 */
h2 {
  font-size: 10pt;
  color: #1E3A5F;
  text-transform: uppercase;
  letter-spacing: 1px;
  border-bottom: 1.5px solid #1E3A5F;
  padding-bottom: 4px;
  margin: 20px 0 10px;
}

/* 테이블 개선 */
.amount-col { text-align: right; }
.total-row td {
  font-weight: bold;
  background: #1E3A5F;
  color: white;
}

/* 서명란 */
.signature-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 20px;
  margin-top: 32px;
}
.signature-box {
  border: 1px solid #d1d5db;
  border-radius: 4px;
  padding: 8px 12px;
  min-height: 70px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}
.signature-box .sig-role {
  font-size: 8pt;
  color: #6b7280;
  font-weight: bold;
  text-transform: uppercase;
  letter-spacing: 0.5px;
}
.signature-box .sig-name {
  font-size: 9pt;
  color: #1a1a1a;
  border-bottom: 1px solid #9ca3af;
  padding-bottom: 2px;
  margin: 16px 0 4px;
}
.signature-box .sig-date {
  font-size: 8pt;
  color: #9ca3af;
}

/* Terms 섹션 */
.terms-section {
  margin-top: 24px;
  padding-top: 12px;
  border-top: 1px solid #e5e7eb;
  font-size: 8pt;
  color: #6b7280;
  line-height: 1.7;
  column-count: 2;
  column-gap: 24px;
}
.terms-section h4 {
  font-size: 8pt;
  font-weight: bold;
  color: #374151;
  margin-bottom: 4px;
  column-span: all;
}

/* 강화된 푸터 */
.footer {
  position: fixed;
  bottom: 0;
  left: 0;
  right: 0;
  background: #1E3A5F;
  color: rgba(255,255,255,0.8);
  font-size: 7.5pt;
  padding: 5px 20mm;
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.footer .footer-left { opacity: 0.9; }
.footer .footer-right { opacity: 0.7; }
```

#### 3.2 body padding 조정

```css
.page { padding: 24mm 20mm 20mm; }  /* 하단 여백 축소 (푸터 공간) */
```

---

### FR-02: quote.html.erb — 견적서 개선

#### 3.3 전체 구조

```erb
<%# 1. 브랜드 바 (레이아웃에서 렌더링, 여기선 doc-meta만) %>

<%# 2. 문서 메타 %>
<div class="doc-meta">
  <div>
    <div class="doc-title">견적서</div>
    <div class="doc-number">QUOTATION · No. QT-<%= @order.id %>-<%= Date.today.strftime("%Y%m%d") %></div>
  </div>
  <div class="doc-date-block">
    <div>발행일: <strong><%= Date.today.strftime("%Y년 %m월 %d일") %></strong></div>
    <div>담당자: <strong><%= @order.assignees.first&.name || @order.user.name %></strong></div>
  </div>
</div>

<%# 3. 유효기간 강조 박스 %>
<div class="highlight-box">
  <div>
    <div class="hl-label">견적 유효기간</div>
    <div class="hl-value"><%= (Date.today + 30.days).strftime("%Y년 %m월 %d일") %>까지</div>
  </div>
  <div style="width:1px;height:30px;background:#93c5fd"></div>
  <div>
    <div class="hl-label">납기 요청일</div>
    <div class="hl-value"><%= @order.due_date&.strftime("%Y년 %m월 %d일") || "미정" %></div>
  </div>
</div>

<%# 4. 발주처 정보 %>
<h2>발주처 정보</h2>
<div class="info-grid">
  <div class="info-item">
    <span class="info-label">발주처 (Client)</span>
    <span class="info-value"><%= @order.client&.name || @order.customer_name %></span>
  </div>
  <div class="info-item">
    <span class="info-label">고객사명</span>
    <span class="info-value"><%= @order.customer_name || "-" %></span>
  </div>
  <div class="info-item">
    <span class="info-label">현장 / 프로젝트</span>
    <span class="info-value"><%= @order.project&.name || "-" %></span>
  </div>
  <div class="info-item">
    <span class="info-label">우선순위</span>
    <span class="info-value">
      <span class="badge badge-<%= @order.priority %>"><%= @order.priority&.upcase %></span>
    </span>
  </div>
</div>

<%# 5. 견적 품목 테이블 %>
<h2>견적 품목</h2>
<table>
  <thead>
    <tr>
      <th width="40%">품목명</th>
      <th width="15%" class="amount-col">수량</th>
      <th width="22%" class="amount-col">단가 (USD)</th>
      <th width="23%" class="amount-col">금액 (USD)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td><%= @order.item_name.presence || @order.title %></td>
      <td class="amount-col"><%= number_with_delimiter(@order.quantity) || 1 %></td>
      <td class="amount-col">
        <% if @order.estimated_value.present? && @order.quantity.to_i > 0 %>
          <%= number_with_delimiter((@order.estimated_value / @order.quantity).round(2)) %>
        <% else %>-<% end %>
      </td>
      <td class="amount-col"><%= number_with_delimiter(@order.estimated_value&.round(2)) || "-" %></td>
    </tr>
    <tr class="total-row">
      <td colspan="3" class="amount-col">합계 (VAT 별도)</td>
      <td class="amount-col">USD <%= number_with_delimiter(@order.estimated_value&.round(2)) || "-" %></td>
    </tr>
  </tbody>
</table>

<% if @order.description.present? %>
  <h2>비고</h2>
  <p style="font-size:10pt;color:#374151;line-height:1.6"><%= @order.description %></p>
<% end %>

<%# 6. 서명란 %>
<h2>서명</h2>
<div class="signature-grid">
  <div class="signature-box">
    <div class="sig-role">작성자 (Prepared by)</div>
    <div class="sig-name">&nbsp;</div>
    <div class="sig-date">날짜: ___________</div>
  </div>
  <div class="signature-box">
    <div class="sig-role">검토 (Reviewed by)</div>
    <div class="sig-name">&nbsp;</div>
    <div class="sig-date">날짜: ___________</div>
  </div>
  <div class="signature-box">
    <div class="sig-role">승인 (Approved by)</div>
    <div class="sig-name">&nbsp;</div>
    <div class="sig-date">날짜: ___________</div>
  </div>
</div>

<%# 7. Terms & Conditions %>
<div class="terms-section">
  <h4>Terms & Conditions</h4>
  <p><strong>1. Validity:</strong> This quotation is valid for 30 days from the date of issue.</p>
  <p><strong>2. Payment:</strong> <%= @order.supplier&.payment_terms || "T/T 30 days after delivery." %></p>
  <p><strong>3. Delivery:</strong> Delivery schedule subject to confirmation upon order placement.</p>
  <p><strong>4. Warranty:</strong> Products are warranted per manufacturer specifications.</p>
  <p><strong>5. Governing Law:</strong> This quotation is governed by the laws of the UAE.</p>
  <p><strong>6. Force Majeure:</strong> AtoZ2010 Inc. shall not be liable for delays caused by circumstances beyond reasonable control.</p>
</div>
```

---

### FR-03: purchase_order.html.erb — 발주서 개선

#### 3.4 전체 구조

```erb
<%# 1. 문서 메타 %>
<div class="doc-meta">
  <div>
    <div class="doc-title">발주서</div>
    <div class="doc-number">PURCHASE ORDER · No. PO-<%= @order.id %>-<%= Date.today.strftime("%Y%m%d") %></div>
  </div>
  <div class="doc-date-block">
    <div>발주일: <strong><%= Date.today.strftime("%Y년 %m월 %d일") %></strong></div>
    <div>담당자: <strong><%= @order.assignees.first&.name || @order.user.name %></strong></div>
  </div>
</div>

<%# 2. 납기일 강조 박스 %>
<div class="highlight-box">
  <div>
    <div class="hl-label">납기 요청일</div>
    <div class="hl-value" style="color:<%= @order.due_date && @order.due_date < Date.today ? '#dc2626' : '#1E3A5F' %>">
      <%= @order.due_date&.strftime("%Y년 %m월 %d일") || "미정" %>
    </div>
  </div>
  <div style="width:1px;height:30px;background:#93c5fd"></div>
  <div>
    <div class="hl-label">결제 조건</div>
    <div class="hl-value"><%= @order.supplier&.payment_terms || "NET 30" %></div>
  </div>
</div>

<%# 3. 공급사 정보 %>
<h2>공급사 정보</h2>
<div class="info-grid">
  <div class="info-item">
    <span class="info-label">공급사 (Supplier)</span>
    <span class="info-value"><%= @order.supplier&.name || "-" %></span>
  </div>
  <div class="info-item">
    <span class="info-label">eCount 코드</span>
    <span class="info-value"><%= @order.supplier&.ecount_code || "-" %></span>
  </div>
  <div class="info-item">
    <span class="info-label">납품 현장</span>
    <span class="info-value"><%= @order.project&.name || "To Be Confirmed" %></span>
  </div>
  <div class="info-item">
    <span class="info-label">발주처 (Client)</span>
    <span class="info-value"><%= @order.client&.name || @order.customer_name || "-" %></span>
  </div>
</div>

<%# 4. 발주 품목 %>
... (기존 테이블 + amount-col 클래스 추가) ...

<%# 5. 서명란 (날짜란 포함) %>
<h2>서명 및 승인</h2>
<div class="signature-grid">
  <div class="signature-box">
    <div class="sig-role">작성자 (Prepared by)</div>
    <div class="sig-name"><%= @order.user.name %></div>
    <div class="sig-date">날짜: ___________</div>
  </div>
  <div class="signature-box">
    <div class="sig-role">검토 (Reviewed by)</div>
    <div class="sig-name">&nbsp;</div>
    <div class="sig-date">날짜: ___________</div>
  </div>
  <div class="signature-box">
    <div class="sig-role">승인 (Approved by)</div>
    <div class="sig-name">&nbsp;</div>
    <div class="sig-date">날짜: ___________</div>
  </div>
</div>

<%# 6. Terms %>
<div class="terms-section">
  <h4>Terms & Conditions</h4>
  <p><strong>1. Acceptance:</strong> This PO constitutes a binding contract upon supplier acceptance.</p>
  <p><strong>2. Payment:</strong> <%= @order.supplier&.payment_terms || "NET 30 days from invoice date." %></p>
  <p><strong>3. Delivery:</strong> Goods must be delivered by the requested delivery date.</p>
  <p><strong>4. Quality:</strong> All goods subject to AtoZ2010 Inc. QA inspection upon receipt.</p>
  <p><strong>5. Cancellation:</strong> Orders may be cancelled with 7 days written notice.</p>
  <p><strong>6. Governing Law:</strong> This PO is governed by the laws of the UAE.</p>
</div>
```

---

### FR-01 상세: pdf.html.erb 브랜드 바

#### 3.5 레이아웃 헤더 추가

`<body>` 안, `.page` 밖에 브랜드 바 삽입:

```html
<body>
  <%# 브랜드 헤더 바 (full-width, page 밖) %>
  <div style="background:#1E3A5F;color:white;padding:9px 20mm;
              display:flex;justify-content:space-between;align-items:center;
              position:fixed;top:0;left:0;right:0;z-index:100;">
    <div>
      <div style="font-size:13pt;font-weight:bold;letter-spacing:0.5px;">
        ■ AtoZ2010 Inc.
      </div>
      <div style="font-size:7.5pt;opacity:0.75;margin-top:1px;">
        Abu Dhabi HQ · Seoul Branch · www.atoz2010.com
      </div>
    </div>
    <div style="font-size:10pt;font-weight:bold;letter-spacing:2px;opacity:0.85;">
      PROCUREMENT
    </div>
  </div>

  <div class="page" style="padding-top:34mm;">  <%# 브랜드 바 높이만큼 추가 %>
    <%= yield %>
  </div>

  <%# 강화된 푸터 %>
  <div style="position:fixed;bottom:0;left:0;right:0;
              background:#1E3A5F;color:rgba(255,255,255,0.8);
              font-size:7.5pt;padding:5px 20mm;
              display:flex;justify-content:space-between;align-items:center;">
    <span>AtoZ2010 Inc. · Abu Dhabi, UAE</span>
    <span>Generated: <%= Date.today.strftime("%Y-%m-%d") %> · Confidential</span>
  </div>
</body>
```

---

## 4. Implementation Order

```
Step 1: app/views/layouts/pdf.html.erb
  - CSS에 brand-bar, doc-meta, highlight-box, signature-grid, terms-section 추가
  - body에 브랜드 헤더 바 + 강화된 푸터 추가
  - page padding-top 조정

Step 2: app/views/orders/pdf/quote.html.erb
  - doc-meta, highlight-box, 서명란, Terms 추가
  - 테이블 amount-col 클래스 적용

Step 3: app/views/orders/pdf/purchase_order.html.erb
  - doc-meta, highlight-box 추가
  - 서명란 날짜란 추가 + @order.user.name 작성자 자동 입력
  - Terms 추가
```

---

## 5. File Summary

| File | Lines (현재) | 변경 내용 |
|------|:---:|-------|
| `app/views/layouts/pdf.html.erb` | ~50 | CSS 대폭 확장 + 브랜드바/푸터 (~+60줄) |
| `app/views/orders/pdf/quote.html.erb` | 76 | doc-meta + highlight-box + 서명란 + Terms (~+50줄) |
| `app/views/orders/pdf/purchase_order.html.erb` | 95 | doc-meta + highlight-box + 서명란 개선 + Terms (~+45줄) |

---

## 6. Completion Criteria

| # | Criteria | FR |
|---|----------|----|
| 1 | PDF에 네이비 브랜드 헤더 바 표시 | FR-01 |
| 2 | 강화된 푸터 (회사명 + 생성일 + Confidential) | FR-01 |
| 3 | 견적서에 유효기간 강조 박스 (파란 테두리) | FR-02 |
| 4 | 견적서에 서명란 3칸 (작성자/검토/승인 + 날짜란) | FR-02 |
| 5 | 견적서에 Terms & Conditions 섹션 (6개 항목) | FR-02 |
| 6 | 발주서에 납기일 강조 박스 (지연 시 빨간색) | FR-03 |
| 7 | 발주서 서명란에 날짜란 포함 + 작성자명 자동 입력 | FR-03 |
| 8 | 발주서에 Terms & Conditions 섹션 (6개 항목) | FR-03 |
| 9 | Gap Analysis Match Rate >= 90% | — |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-28 | Initial design | bkit:pdca |
