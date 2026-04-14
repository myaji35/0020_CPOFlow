# 칸반 카드 상태 범례 커스터마이즈 — 설계안

**작성일**: 2026-04-14
**작성자**: Claude (Opus 4.6) + 대표님 협의
**상태**: Draft → 승인 대기

---

## 1. 배경과 목표

### 1.1 현재 상태
- `Order.priority`는 Ruby enum 정수(0~3) 고정값: `low/medium/high/urgent`
- 칸반 카드의 배경·보더 색상은 `app/views/kanban/_card.html.erb`에 하드코딩
- 범례 추가·색상 변경은 코드 수정 + 배포가 필요

### 1.2 목표
사용자가 **Settings 화면에서 직접**:
- 상태 라벨 텍스트를 수정
- 상태를 추가·삭제 (삭제는 해당 상태를 쓰는 카드가 0개일 때만)
- 각 상태에 카드 배경·보더·텍스트 색상을 지정
- AtoZ 업무에 맞는 **7개 샘플 프리셋**이 seed로 설치
- 카드에 상태를 **임의로 부여** (수동 변경 가능)
- AI가 마감일 기반으로 상태를 **자동 제안**하는 규칙도 Settings에서 편집

### 1.3 비목표 (Out of Scope)
- 상태별 워크플로우 자동화(상태 변경 시 알림, 승인 체인 등)는 별도 이슈
- 다국어 상태 라벨은 1차 범위 외 (한국어/영어 토글은 Settings에서 전역 locale로 이미 처리)
- 역할별(admin/member) 상태 접근 제어는 범위 외 (전원 동등하게 편집 가능)

---

## 2. 결정 사항 요약

| Q | 결정 | 근거 |
|---|---|---|
| Q1. 데이터 모델 | **A안 — 완전 교체** | 시스템 초기로 데이터 리스크 낮음, enum 확장성 한계 명확 |
| Q2. (A안 택함으로 스킵) | — | — |
| Q3. 색상 편집 방식 | **C안 — 하이브리드 팔레트** | 기본 프리셋 + 고급 자유 입력으로 일관성/자유도 양립 |
| Q4. 샘플 프리셋 | **B안 — 7개 워크플로우** | CPO 실제 업무(VIP/보류/기한초과) 반영 |
| Q5. 자동 배정 규칙 | **A안 — DB 기반 auto_rule 유지** | 기존 AI 배정 로직 승계, 임계값도 편집 가능 |

---

## 3. 데이터 모델

### 3.1 신규 테이블: `card_statuses`

| 컬럼 | 타입 | 설명 |
|---|---|---|
| `id` | bigint PK | |
| `key` | string (unique) | 내부 식별자 (slug). 예: `urgent`, `vip`, `hold` |
| `name` | string | 표시 라벨. 예: "긴급", "VIP 고객", "대기/보류" |
| `bg_color` | string(7) | HEX 배경색. 예: `#FFF1F2` |
| `border_color` | string(7) | HEX 보더색. 예: `#FECDD3` |
| `text_color` | string(7) | HEX 텍스트색. 예: `#991B1B` |
| `position` | integer | 정렬 순서 (드래그 재배치 지원) |
| `is_system` | boolean | 시스템 기본 제공 여부 (UI에서 "삭제" 버튼 비활성화 단, **rename·색상 변경은 가능**) |
| `is_default` | boolean | 신규 카드 생성 시 기본값으로 사용할 상태. 항상 **정확히 1건만 true** |
| `auto_rule` | jsonb | AI 자동 배정 규칙 (3.3 참조). `null`이면 수동 전용 |
| `auto_priority` | integer | 자동 배정 우선순위(여러 규칙 동시 해당 시 높은 값 우선). 기본 0 |
| `created_at`, `updated_at` | datetime | |

**인덱스**:
- `UNIQUE(key)`
- `INDEX(position)`
- 부분 UNIQUE: `is_default=true` 인 레코드는 1건만 (DB 레벨 보장)

### 3.2 `orders` 테이블 변경

```
ADD COLUMN card_status_id BIGINT NULL REFERENCES card_statuses(id)
ADD INDEX (card_status_id)
```

**enum `priority` 제거 흐름**:
1. 마이그레이션 1: `card_status_id` 추가, seed 7개 프리셋 삽입
2. 마이그레이션 2(데이터): 기존 `priority` 값 → 대응되는 `CardStatus.key`로 매핑 후 `card_status_id` 채움
   - `urgent` → 긴급, `high` → 높음, `medium` → 보통, `low` → 낮음
3. 마이그레이션 3: `priority` 컬럼 drop (시스템 초기 가정이므로 즉시 drop)

> **롤백 안전장치**: 마이그레이션 2 이후 7일간 `priority_legacy` 이름으로 보존하는 선택지도 있으나, 대표님 "시스템 초기" 확인으로 즉시 drop 택함.

### 3.3 `auto_rule` JSON 스키마

```json
{
  "when": "due_date",          // 적용 대상 (현재: due_date만)
  "operator": "lte",           // lte | gte | between
  "value": 3,                  // 일(日) 단위
  "require_assignee": false    // 담당자 미배정일 때만 적용할지 (현재 urgent_unassigned? 로직 승계)
}
```

**해석 예시**:
- `{when: "due_date", operator: "lte", value: 3}` → "마감 3일 이내면 이 상태로 자동 배정"
- `{when: "due_date", operator: "lte", value: 7}` → "마감 7일 이내면 이 상태" (3일 규칙과 동시 해당 시 `auto_priority` 높은 쪽 채택)
- `auto_rule: null` → VIP·보류 같은 **수동 전용** 상태

**자동 배정 시점**:
- Order 생성 시 1회
- Order의 `due_date` 변경 시
- 일간 배치 Job (`CardStatusAutoAssignJob`, Solid Queue 크론)이 마감일 경과·임박 카드 재평가

**사용자가 수동 배정하면 자동 배정 로직이 덮어쓰지 않음**: `card_status_manually_set_at` 타임스탬프를 orders에 추가해, 이 값이 있으면 자동 배정 스킵.

---

## 4. 초기 샘플 프리셋 (seed) — 7개

| # | key | 라벨 | bg | border | text | is_system | auto_rule | auto_priority |
|---|---|---|---|---|---|---|---|---|
| 1 | `urgent` | 긴급 | `#FFF1F2` | `#FECDD3` | `#991B1B` | ✅ | `{when:"due_date", operator:"lte", value:3}` | 30 |
| 2 | `high` | 높음 | `#FFF7ED` | `#FED7AA` | `#9A3412` | ✅ | `{when:"due_date", operator:"lte", value:7}` | 20 |
| 3 | `normal` | 보통 (기본값) | `#FAFAFA` | `#E5E7EB` | `#374151` | ✅ | null | 0 |
| 4 | `low` | 낮음 | `#F0FDF4` | `#BBF7D0` | `#14532D` | ✅ | null | 0 |
| 5 | `vip` | VIP 고객 | `#F5F3FF` | `#DDD6FE` | `#5B21B6` | ❌ | null (수동) | 0 |
| 6 | `hold` | 대기/보류 | `#FEFCE8` | `#FEF08A` | `#854D0E` | ❌ | null (수동) | 0 |
| 7 | `overdue` | 기한초과 | `#FEE2E2` | `#FCA5A5` | `#7F1D1D` | ❌ | `{when:"due_date", operator:"lte", value:0}` | 40 |

- `normal`이 `is_default=true` (신규 카드 기본값)
- 시스템(`is_system=true`) 4개는 삭제 불가, rename·색상 변경은 가능
- 사용자 추가(`is_system=false`) 3개는 전부 삭제 가능 (카드 0건 조건)

---

## 5. UI 설계

### 5.1 Settings 진입점
- 경로: `/settings/card_statuses`
- 좌측 Settings 사이드바에 "칸반 상태 관리" 메뉴 추가 (`menu_permissions`에 등록)

### 5.2 Settings 화면 구성

```
┌─────────────────────────────────────────────────────────────┐
│  칸반 상태 관리                              [+ 새 상태 추가] │
├─────────────────────────────────────────────────────────────┤
│  [≡] 🔴 긴급       (시스템)   자동: 3일 이내   [편집] [X]     │
│  [≡] 🟠 높음       (시스템)   자동: 7일 이내   [편집] [X]     │
│  [≡] ⬜ 보통 ★기본  (시스템)   수동            [편집] [X]     │
│  [≡] 🟢 낮음       (시스템)   수동            [편집] [X]     │
│  [≡] 🟣 VIP 고객            수동 (12건 사용)   [편집] [X]     │
│  [≡] 🟡 대기/보류           수동 (3건 사용)    [편집] [X]     │
│  [≡] 🔴 기한초과            자동: 마감 경과     [편집] [X]     │
├─────────────────────────────────────────────────────────────┤
│  💡 '시스템' 상태는 라벨·색상은 수정 가능, 삭제는 불가합니다.    │
│     삭제는 해당 상태를 쓰는 카드가 0건일 때만 가능합니다.         │
└─────────────────────────────────────────────────────────────┘
```

- `[≡]` 드래그 핸들로 순서 변경 (Sortable.js, 기존 kanban 드래그와 동일 패턴)
- `[X]` 삭제 버튼: `is_system=true`이면 렌더 안 함, 사용 카드>0이면 disabled + 툴팁 "사용 중인 카드 N건 있음"
- "이름 수정"은 행에서 **인라인 더블클릭 편집** → 바로 저장 (대표님 "상태명 수정은 바로 가능" 요구 반영)

### 5.3 편집 모달 (색상 변경 + auto_rule)

```
┌──────── 상태 편집: VIP 고객 ─────────┐
│                                      │
│  라벨 이름: [VIP 고객          ]      │
│                                      │
│  색상 프리셋 (12개):                   │
│   ⬜ 회색  🔵 파랑  🟢 초록  🟡 노랑    │
│   🟠 주황  🔴 빨강  🟣 보라  🔵 청록    │
│   🌸 분홍  🟤 갈색  ⚫ 검정  🟦 남색    │
│                                      │
│  [▼ 커스텀 색상 직접 지정]             │
│   배경: [#F5F3FF] [🎨]                │
│   보더: [#DDD6FE] [🎨]                │
│   글자: [#5B21B6] [🎨]                │
│                                      │
│  👁️ 미리보기:                         │
│  ┌────────────────────┐              │
│  │ VIP 고객            │              │
│  │ Nawah PO 4500019... │              │
│  │ 2026-04-20 마감     │              │
│  └────────────────────┘              │
│                                      │
│  자동 배정 규칙:                       │
│   ⚪ 수동 전용                        │
│   ⚪ 마감일 기준: [  ] 일 이내          │
│   ⚪ 마감일 기준: 마감 경과 시          │
│                                      │
│  우선순위(동시 적용 시): [  0]          │
│                                      │
│            [취소]  [저장]              │
└──────────────────────────────────────┘
```

- 팔레트 12개는 `CardStatus::COLOR_PRESETS` 상수로 관리 (`{bg, border, text}` 세트)
- "커스텀 색상 직접 지정"은 기본 접혀있음, 클릭 시 확장 (하이브리드 C안 정확 구현)
- 실시간 미리보기는 Stimulus 컨트롤러로 3개 input 변경 시 카드 스타일 재계산
- 자동 배정은 라디오로 3가지만 (수동/N일 이내/경과)

### 5.4 카드에서 수동 상태 변경

- 칸반 카드 우클릭 또는 드로어의 "상태" 필드
- 드롭다운으로 현재 정의된 모든 `CardStatus` 표시 → 선택 즉시 저장
- 수동 변경 시 `card_status_manually_set_at = now()` 기록하여 이후 자동 배정이 덮어쓰지 않음
- 드로어에 "🔄 자동 배정으로 되돌리기" 링크 → `card_status_manually_set_at = null` 리셋

### 5.5 칸반 본체 변경

- `_card.html.erb`의 하드코딩 case문 제거, `order.card_status.bg_color` 등을 style로 주입
- 상단 범례 필터 버튼도 `CardStatus.ordered` 로 동적 렌더링
- `data-priority="urgent"` → `data-card-status-key="urgent"`로 변경

---

## 6. 아키텍처 / 컴포넌트

### 6.1 컴포넌트

| 계층 | 파일 | 역할 |
|---|---|---|
| Model | `app/models/card_status.rb` | 상태 정의, `deletable?`, `auto_applies_to?(order)` |
| Service | `app/services/card_status/auto_assigner.rb` | Order 하나에 대해 규칙 평가 후 적절한 `CardStatus` 반환 |
| Job | `app/jobs/card_status_auto_assign_job.rb` | 일간 배치, 마감 임박 카드 재평가 |
| Controller | `app/controllers/settings/card_statuses_controller.rb` | Settings CRUD (index/create/update/destroy/reorder) |
| View | `app/views/settings/card_statuses/index.html.erb` | 리스트 + 인라인 편집 + 드래그 |
| View | `app/views/settings/card_statuses/_edit_modal.html.erb` | 편집 모달 |
| Stimulus | `app/javascript/controllers/card_status_preview_controller.js` | 실시간 미리보기 |
| Concern | `app/controllers/concerns/with_card_statuses.rb` | 칸반/인박스 컨트롤러에서 상태 목록 공유 |
| Seed | `db/seeds/card_statuses.rb` | 7개 프리셋 시드 |
| Constants | `lib/card_status_color_presets.rb` | 12개 팔레트 정의 |

### 6.2 자동 배정 데이터 흐름

```
[Order 저장 시]
    ↓
  after_save :maybe_auto_assign_card_status
    ↓
  card_status_manually_set_at 있음? → skip
    ↓
  CardStatus::AutoAssigner.call(order)
    ├─ CardStatus.where.not(auto_rule: nil).order(auto_priority: :desc)
    ├─ 각 rule 평가 → 첫 매칭 반환
    └─ 매칭 없으면 CardStatus.default (normal)
    ↓
  order.update_column(:card_status_id, result.id)

[일간 배치 — 크론 02:00 KST]
    ↓
  CardStatusAutoAssignJob.perform_now
    ↓
  Order.where(card_status_manually_set_at: nil)
       .where.not(status: [:get_grn, :give_up, :done])
       .find_each { |o| reassess(o) }
```

### 6.3 삭제 규칙

```ruby
def deletable?
  !is_system? && orders.empty?
end

# Controller#destroy
if card_status.deletable?
  card_status.destroy
  redirect with notice
else
  redirect with alert(
    is_system? ? "시스템 내장 상태는 삭제할 수 없습니다" :
    "이 상태를 사용 중인 카드 #{orders.count}건이 있습니다"
  )
end
```

**Race condition 방지**: 삭제 트랜잭션 안에서 `lock!` + `orders.count == 0` 재확인.

---

## 7. 에러 처리

| 시나리오 | 처리 |
|---|---|
| `normal` (기본값) 삭제 시도 | UI에서 버튼 비활성 + 서버 `is_default=true` 조건 포함해 차단 |
| 모든 상태 삭제되어 0개 | DB 제약: `is_default=true` 레코드는 항상 1건 강제 → 0개 불가 |
| 자동 배정 대상 상태(auto_rule)가 모두 삭제됨 | fallback → `CardStatus.default` |
| HEX 색상 유효성 | 정규식 `/\A#[0-9A-Fa-f]{6}\z/` + 서버 검증, UI는 input type=color |
| 라벨 중복 | `name` uniqueness 검증, 동일 이름 시 "이미 존재합니다" 에러 |
| 자동 배정 Job 실패 | 로그 경고만 남기고 다음 카드 진행 (개별 실패가 전체 배치 중단 안 됨) |
| priority 마이그레이션 시 미매핑 값 | 기본 `normal`로 채움 + 로그 |

---

## 8. 테스트 전략

### 8.1 Model 테스트 (`test/models/card_status_test.rb`)
- `deletable?`: system / 사용 중 / 사용 안 함 3케이스
- `default` scope: 정확히 1개 반환
- `auto_applies_to?(order)`: due_date lte/gte 경계값 (0일, 3일 정확, 4일 미적용)
- 삭제 시 `is_default=true`이면 실패

### 8.2 Service 테스트 (`test/services/card_status/auto_assigner_test.rb`)
- 여러 규칙 동시 해당 시 `auto_priority` 높은 것 선택
- `card_status_manually_set_at` 있으면 건드리지 않음
- 매칭 없으면 default 반환

### 8.3 Controller 테스트 (`test/controllers/settings/card_statuses_controller_test.rb`)
- CRUD + reorder
- 삭제 불가 조건(시스템/사용 중)에서 422
- 인라인 rename (PATCH name only)

### 8.4 System 테스트 (`test/system/card_status_management_test.rb`)
- Settings 진입 → 라벨 더블클릭 수정 → 저장
- 모달 열고 팔레트 선택 → 미리보기 변경 확인
- 드래그로 순서 변경 → 칸반 페이지에서 순서 반영 확인
- 삭제 가능한 상태 vs 불가능한 상태 UI

### 8.5 회귀 테스트
- 기존 `test/models/order_test.rb`의 priority 관련 테스트 → `card_status` 기반으로 갱신
- 기존 `urgent_unassigned?` → `card_status.key == "urgent"` 로 전환 확인
- RFQ AI가 priority 설정하던 로직 → `CardStatus::AutoAssigner`를 통하게 전환

---

## 9. 마이그레이션 순서 (안전 배포)

```
Step 1. card_statuses 테이블 생성 + 7개 seed
Step 2. orders.card_status_id 컬럼 추가 (nullable, 기본 normal)
Step 3. 데이터 이관: 기존 priority → card_status_id 매핑
Step 4. 모델/뷰/컨트롤러/서비스 코드 전환 (priority 참조 전부 제거)
Step 5. Settings UI 공개
Step 6. 회귀 테스트 통과 확인 후 orders.priority 컬럼 drop
```

**각 Step마다 배포 가능** — Step 3까지는 구 코드가 여전히 동작, Step 4부터 새 시스템 가동.

---

## 10. 영향 범위 (리팩터 대상 파일)

**priority 참조 전수 조사** (조사 완료):
- `app/models/order.rb` — enum, scope, 메서드 8곳
- `app/views/kanban/_card.html.erb` — bg/border 하드코딩
- `app/views/kanban/index.html.erb` — 필터 버튼, data-priority 참조
- `app/views/orders/_drawer_content.html.erb` — 뱃지
- `app/helpers/orders_helper.rb` — `priority_badge` 헬퍼
- `app/services/gmail/rfq_detector_service.rb` — AI 배정 결과를 priority로 넣던 지점
- `app/services/gmail/classification/*` — v2 AI 분류에서 priority 설정하던 곳

모두 `order.card_status` 기반으로 전환. 전환 체크리스트는 구현 단계에서 작성.

---

## 11. 범위 체크

- [x] 단일 구현 플랜으로 소화 가능한 범위 (테이블 1개 + 기존 컬럼 1개 전환 + Settings CRUD UI + 자동 배정 서비스)
- [x] 회귀 테스트 영역 명확 (priority 참조 전수)
- [x] 독립 서브 프로젝트로 분할 불필요 — 기존 워크플로우 수정이 단일 주제

---

## 12. 열린 이슈 / 추후 과제

1. **다국어 상태 라벨**: 현재 설계는 단일 문자열. i18n이 필요하면 `name_en`/`name_ko` 컬럼 분리 또는 `locale_names: jsonb` 구조로 확장
2. **역할별 상태 접근 제한**: admin만 편집 가능하게 할지 등은 별도 이슈
3. **상태 변경 히스토리**: Activity 모델에 "status_changed_from→to" 기록은 별도 이슈 (현재 Activity에 action 문자열만 저장되는 구조 확인됨)
4. **자동 배정 규칙 확장**: `when: "supplier_tier"`, `when: "client_grade"` 등 다른 조건 추가는 auto_rule JSON 스키마 확장으로 대응 가능

---

## 13. 승인 체크포인트

- [ ] 섹션 1~4 (목표/모델/프리셋) 승인
- [ ] 섹션 5 (UI 설계) 승인
- [ ] 섹션 6~9 (아키텍처/테스트/마이그레이션) 승인
- [ ] 전체 스펙 확정 → 구현 플랜 작성 진입 (`superpowers:writing-plans`)
