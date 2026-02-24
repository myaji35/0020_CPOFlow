# Design: RFQ AI Pipeline

## Architecture

### 3단계 판정 흐름
```
이메일 수신
  ↓
① excluded_sender? / excluded_subject? → 즉시 제외
  ↓
② LlmRfqAnalyzerService (컨텍스트 강화)
   - 과거 발주처 이력 주입 (RfqFeedback 패턴)
   - score >= 70 → :confirmed
   - score 30~69 → :uncertain
   - score < 30  → :excluded
  ↓
③ :confirmed  → EmailToOrderService.create_order! (자동)
   :uncertain  → Order(status: :inbox, rfq_status: :uncertain) 생성
   :excluded   → 스킵
```

### DB 스키마

#### rfq_feedbacks 테이블 (신규)
```ruby
create_table :rfq_feedbacks do |t|
  t.references :order,       null: false
  t.references :user,        null: false
  t.string  :verdict,        null: false   # "confirmed" | "rejected"
  t.string  :sender_domain                 # 학습용 발신 도메인
  t.string  :subject_pattern               # 학습용 제목 패턴 (첫 20자)
  t.text    :note                          # 사용자 메모 (선택)
  t.timestamps
end
```

#### orders 테이블 컬럼 추가
```ruby
add_column :orders, :rfq_status, :integer, default: 0
# enum: { confirmed: 0, uncertain: 1, excluded: 2 }

add_column :orders, :reply_draft, :text
# 자동 생성된 답변 초안 (한/영)
```

### 서비스 설계

#### RfqFeedbackService
```ruby
# 피드백 저장 + few-shot 패턴 반환
RfqFeedbackService.record!(order, user, verdict: "confirmed")
RfqFeedbackService.few_shot_examples(limit: 5)
# => [{ subject:, from:, verdict:, reason: }, ...]
```

#### LlmRfqAnalyzerService (강화)
- few-shot examples를 프롬프트에 주입
- 발주처 이력(같은 도메인 과거 확정 건수) 컨텍스트 추가
- 판정 결과에 :rfq_status (:confirmed/:uncertain/:excluded) 포함

#### RfqReplyDraftService
```ruby
# Gemini API로 답변 초안 생성
RfqReplyDraftService.generate!(order)
# => "Dear [Name],\nThank you for your RFQ..."
```
- 언어 자동 감지 (이메일 본문 언어 기반)
- 템플릿: 수신 확인 + 검토 예정일 (수신일 + 2영업일)
- Order#reply_draft 컬럼에 저장

### Inbox UI 변경

#### 탭 구조 변경
```
기존: [전체] [RFQ] [전환됨]
변경: [전체] [RFQ] [확인 필요 🔴N] [전환됨]
```

#### 확인 필요 카드 UI
- 노란색 테두리 + "AI 판정 불확실" 뱃지
- [✅ RFQ 맞음] [❌ RFQ 아님] 버튼
- 클릭 시 AJAX → FeedbackController → 즉시 UI 업데이트

#### 답변 초안 패널 (번역 탭 옆 신규 탭)
```
[원문] [번역] [답변 초안] ← 신규
```
- RFQ confirmed 시 자동 생성
- "복사" 버튼으로 클립보드 복사

### 라우트 추가
```ruby
post "inbox/:id/feedback", to: "inbox#feedback", as: :inbox_feedback
post "inbox/:id/generate_reply", to: "inbox#generate_reply", as: :inbox_generate_reply
```

### 담당자 자동 배정 로직
```ruby
# 같은 발주처(이메일 도메인)의 가장 최근 Order 담당자를 배정
last_order = Order.where("original_email_from LIKE ?", "%#{domain}%")
                  .where.not(assignees: nil)
                  .order(created_at: :desc).first
order.assignees << last_order.assignees.first if last_order
```

## File List
| 파일 | 작업 |
|------|------|
| `db/migrate/..._add_rfq_status_to_orders.rb` | 신규 |
| `db/migrate/..._create_rfq_feedbacks.rb` | 신규 |
| `app/models/rfq_feedback.rb` | 신규 |
| `app/models/order.rb` | rfq_status enum, reply_draft 추가 |
| `app/services/gmail/rfq_feedback_service.rb` | 신규 |
| `app/services/gmail/rfq_reply_draft_service.rb` | 신규 |
| `app/services/gmail/llm_rfq_analyzer_service.rb` | 강화 |
| `app/services/gmail/rfq_detector_service.rb` | 3단계 판정 |
| `app/services/gmail/email_to_order_service.rb` | confirmed 자동 생성 |
| `app/controllers/inbox_controller.rb` | feedback, generate_reply 액션 |
| `app/views/inbox/index.html.erb` | 확인 필요 탭 + 피드백 버튼 + 초안 패널 |
| `config/routes.rb` | 라우트 추가 |
