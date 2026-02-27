# notification-ux Plan

## 1. Feature Overview

**Feature Name**: notification-ux
**Created**: 2026-02-28
**Priority**: High
**Estimated Scope**: Small-Medium (2~3 files)

### 1.1 Summary

알림 센터 UX 개선 — 현재 `/notifications` 페이지로만 제공되는 알림을 헤더 드롭다운 패널로 확장하고, 알림 목록의 시각적 품질을 높인다.

### 1.2 Problem Statement

현재 알림 기능의 문제점:
1. **헤더 벨 아이콘**: 클릭 시 `/notifications` 전체 페이지로 이동 → 컨텍스트 이탈
2. **알림 목록**: 읽음/안읽음 시각 구분이 `opacity-60`만으로 약함
3. **notifiable 클릭**: `"주문 보기 →"` 링크가 전체 페이지 이동 → `openOrderDrawer()` 미연동
4. **타입 필터 없음**: 전체 목록만 표시 (납기/상태변경/배정/시스템 구분 불가)
5. **system 타입 아이콘**: 현재 미구현 (TYPES에 있으나 아이콘 없음)

---

## 2. Goals

### 2.1 Primary Goals

1. **헤더 드롭다운 패널** (FR-01): 벨 아이콘 클릭 → 슬라이드 드롭다운으로 최근 10개 표시
2. **읽음 상태 시각화 강화** (FR-02): 안읽음 = 좌측 파란 점 + 배경 강조, 읽음 = 일반
3. **openOrderDrawer 연동** (FR-03): notifiable이 Order인 경우 드로어 오픈
4. **타입 필터 탭** (FR-04): 전체/납기/상태변경/배정 탭으로 필터링
5. **system 타입 아이콘 추가** (FR-05): 시스템 알림용 아이콘 완성

### 2.2 Out of Scope

- 실시간 WebSocket 푸시 알림 (ActionCable — Phase 2)
- 알림 설정 (어떤 타입 수신할지 선택)
- 이메일 알림

---

## 3. Functional Requirements

### FR-01: 헤더 알림 드롭다운 패널

**트리거**: `shared/_header.html.erb` 벨 아이콘 클릭
**현재**: `link_to notifications_path` (페이지 이동)
**변경**: `button` + JS 드롭다운 패널

드롭다운 내용:
- 헤더: "알림" 제목 + "모두 읽음" 버튼 + "전체 보기 →" 링크
- 최근 알림 10개 (타입 아이콘 + 제목 + 시간 + 읽음 상태)
- 안읽음 없을 때: "새 알림이 없습니다" 빈 상태

패널 닫기: 외부 클릭, Escape 키

### FR-02: 읽음 상태 시각화

| 상태 | 현재 | 변경 |
|------|------|------|
| 안읽음 | `opacity-60` 제거 | 좌측 `w-1.5 h-1.5 bg-primary rounded-full` 점 + `bg-blue-50 dark:bg-blue-900/20` 배경 |
| 읽음 | 기본 스타일 | `bg-white dark:bg-gray-900` 배경 + 점 없음 |

### FR-03: openOrderDrawer 연동

`notifications/index.html.erb`의 Order 링크:
- 현재: `link_to "주문 보기 →", order_path(order)` (페이지 이동)
- 변경: `onclick="openOrderDrawer(<id>, <title_json>, '<path>')"` cursor-pointer

### FR-04: 타입 필터 탭 (index 페이지)

탭 목록:
- 전체 (기본)
- 납기 (`due_date`)
- 상태변경 (`status_changed`)
- 배정 (`assigned`)

JS 기반 필터 (서버 요청 없이 DOM filter)

### FR-05: system 타입 아이콘

`notification.rb` TYPES에 `system`이 있으나 뷰에서 아이콘 미구현.
추가: 설정/시스템 아이콘 (settings/info 스타일)

---

## 4. Technical Approach

### 4.1 Files to Modify

| File | Change |
|------|--------|
| `app/views/shared/_header.html.erb` | 벨 아이콘 → 드롭다운 버튼 + 패널 |
| `app/views/notifications/index.html.erb` | 읽음 시각화 + 드로어 연동 + 타입 필터 탭 + system 아이콘 |

### 4.2 No Controller Change Required

- 드롭다운 패널: `current_user.notifications.unread.recent.limit(10)` — 헤더에서 직접 쿼리 (이미 패턴 있음)
- 타입 필터: JS DOM 필터 (서버 요청 없음)
- 읽음 처리: 기존 `read` / `read_all` 라우트 재사용

### 4.3 JS Pattern

```javascript
// 드롭다운 토글
function toggleNotificationPanel() {
  const panel = document.getElementById('notification-panel');
  panel.classList.toggle('hidden');
}

// 외부 클릭 닫기
document.addEventListener('click', (e) => {
  if (!e.target.closest('#notification-bell')) {
    document.getElementById('notification-panel')?.classList.add('hidden');
  }
});
```

---

## 5. Completion Criteria

| # | Criteria |
|---|----------|
| 1 | 헤더 벨 클릭 → 드롭다운 패널 표시 (최근 10개) |
| 2 | 드롭다운 외부 클릭/Escape → 닫힘 |
| 3 | 안읽음 알림 = 파란 점 + 배경 강조 |
| 4 | Order 알림 클릭 → openOrderDrawer 실행 |
| 5 | index 페이지 타입 필터 탭 동작 |
| 6 | system 타입 아이콘 표시 |
| 7 | Gap Analysis Match Rate >= 90% |

---

## 6. Dependencies

- `openOrderDrawer()` 함수 (layouts/application.html.erb L152) — 기존 존재
- `notifications#read`, `notifications#read_all` 라우트 — 기존 존재
- `current_user.notifications.unread` scope — 기존 존재

---

## Version History

| Version | Date | Author |
|---------|------|--------|
| 1.0 | 2026-02-28 | bkit:pdca |
