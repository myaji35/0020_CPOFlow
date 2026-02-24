# frozen_string_literal: true

module Gmail
  # 사용자 RFQ 피드백 저장 + few-shot 패턴 관리
  #
  # Usage:
  #   Gmail::RfqFeedbackService.record!(order, user, verdict: "confirmed")
  #   Gmail::RfqFeedbackService.few_shot_examples(limit: 5)
  class RfqFeedbackService
    # 피드백 저장 + Order rfq_status 업데이트
    def self.record!(order, user, verdict:, note: nil)
      domain = order.original_email_from.to_s.match(/@([^>]+)>?/)&.[](1)&.strip&.downcase
      subject_pattern = order.original_email_subject.to_s.first(20)

      feedback = RfqFeedback.find_or_initialize_by(order: order, user: user)
      feedback.update!(
        verdict:        verdict,
        sender_domain:  domain,
        subject_pattern: subject_pattern,
        note:           note
      )

      # Order rfq_status 업데이트
      new_rfq_status = verdict == "confirmed" ? :rfq_confirmed : :rfq_excluded
      order.update_column(:rfq_status, Order.rfq_statuses[new_rfq_status])

      feedback
    end

    # few-shot 예시 반환 (LLM 프롬프트 주입용)
    def self.few_shot_examples(limit: 5)
      RfqFeedback.includes(:order)
                 .recent
                 .limit(limit * 2)
                 .map do |fb|
        {
          subject:  fb.order.original_email_subject.to_s.truncate(60),
          from:     fb.sender_domain.to_s,
          verdict:  fb.verdict,
          reason:   fb.note.presence || (fb.verdict == "confirmed" ? "사용자가 RFQ로 확인" : "사용자가 RFQ 아님으로 표시")
        }
      end.first(limit)
    end

    # 특정 도메인의 과거 확정 건수 (컨텍스트 강화용)
    def self.domain_history(sender_domain)
      return { confirmed: 0, rejected: 0 } if sender_domain.blank?

      feedbacks = RfqFeedback.where(sender_domain: sender_domain)
      {
        confirmed: feedbacks.confirmed.count,
        rejected:  feedbacks.rejected.count
      }
    end
  end
end
