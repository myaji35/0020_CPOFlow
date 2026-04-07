# frozen_string_literal: true

module Gmail
  # 사용자 RFQ 피드백 저장 + few-shot 패턴 관리
  #
  # Usage:
  #   Gmail::RfqFeedbackService.record!(order, user, verdict: "confirmed")
  #   Gmail::RfqFeedbackService.few_shot_examples(limit: 5)
  class RfqFeedbackService
    # Phase E: Few-shot 정적 예시 20건
    # 사용자 피드백이 누적되기 전(콜드 스타트)에도 LLM 분류 품질을 안정적으로 확보
    # rfq_confirmed 12건 + rfq_rejected 8건 (RFQ 우세 + 노이즈 케이스)
    STATIC_EXAMPLES = [
      # ============ confirmed (RFQ 맞음) 12건 ============
      { subject: "Request for Quotation - Sika Waterproofing Membrane", from: "procurement.adnoc.ae", verdict: "confirmed",
        reason: "명시적 RFQ 키워드 + Sika 제품 명시 + 발주처 도메인" },
      { subject: "RFQ for Concrete Admixture (5,000 kg)", from: "purchasing.kepco.co.kr", verdict: "confirmed",
        reason: "RFQ + 수량 명시 + 한전 구매부서" },
      { subject: "Inquiry - Epoxy Adhesive for Bridge Project Doha", from: "tenders.qatarrail.qa", verdict: "confirmed",
        reason: "Inquiry + 제품(Epoxy) + 프로젝트 명칭" },
      { subject: "견적 요청 - 폴리우레탄 실란트 200카트리지", from: "buyer.samsungeng.com", verdict: "confirmed",
        reason: "한국어 견적요청 + 수량 + 대형 EPC" },
      { subject: "Quotation needed: Sikaflex-1a 600ml x 480 cartridges", from: "procurement.hyundai-eng.com", verdict: "confirmed",
        reason: "Quotation needed + 정확한 SKU + 수량" },
      { subject: "Tender CT/2026/045 - Repair Mortar 12 tons", from: "tender.adport.ae", verdict: "confirmed",
        reason: "Tender 번호 + 자재 + 수량" },
      { subject: "Please send your best price for Sika Grout 212", from: "info.aldarproperties.ae", verdict: "confirmed",
        reason: "best price + 정확 제품명" },
      { subject: "Pricing Request - Concrete Repair System (Sika MonoTop)", from: "engineering.dubaimetro.ae", verdict: "confirmed",
        reason: "Pricing Request + 제품군" },
      { subject: "Bid Invitation: Waterproofing Materials Phase 2", from: "tenders.neom.sa", verdict: "confirmed",
        reason: "Bid Invitation + 자재 카테고리" },
      { subject: "Material Request - SikaTop Seal 107 (3,000 kg)", from: "site.lottecon.com", verdict: "confirmed",
        reason: "Material Request + 정확 제품 + 수량" },
      { subject: "URGENT - Need quotation for sealant before Friday", from: "pm.binladin.sa", verdict: "confirmed",
        reason: "Urgent + quotation + 마감일" },
      { subject: "RFQ-2026-0033 Sikadur 31 EF Normal", from: "procurement.shapoorji.ae", verdict: "confirmed",
        reason: "RFQ 번호 + 정확 SKU" },

      # ============ rejected (RFQ 아님) 8건 ============
      { subject: "Newsletter: Sika Q1 2026 Product Updates", from: "marketing.sika.com", verdict: "rejected",
        reason: "Newsletter — 마케팅 발송, 견적 의도 없음" },
      { subject: "Invoice #INV-2026-1192 - Payment due", from: "accounts.dhl.com", verdict: "rejected",
        reason: "청구서 — 견적과 무관" },
      { subject: "Re: Order delivered - POD attached", from: "logistics.aramex.ae", verdict: "rejected",
        reason: "배송완료 통지" },
      { subject: "Auto-reply: Out of Office until March 30", from: "noreply.gmail.com", verdict: "rejected",
        reason: "자동응답 — 사람 발송 아님" },
      { subject: "Webinar invitation: Construction Chemicals 2026", from: "events.constructionweek.com", verdict: "rejected",
        reason: "웨비나 초청 — 견적 아님" },
      { subject: "Bank statement March 2026 - AtoZ2010 LLC", from: "ebanking.adcb.ae", verdict: "rejected",
        reason: "은행 명세서" },
      { subject: "Job application - Sales Engineer position", from: "applicant.gmail.com", verdict: "rejected",
        reason: "구직 지원" },
      { subject: "Visa renewal reminder for employee", from: "hr.atoz2010.ae", verdict: "rejected",
        reason: "내부 HR 알림" }
    ].freeze

    # 피드백 저장 + Order rfq_status 업데이트
    # ai_score: 판정 당시 AI 가 부여한 confidence (0.0~1.0). order 에서 자동 추출 시도.
    def self.record!(order, user, verdict:, note: nil, ai_score: nil)
      domain = order.original_email_from.to_s.match(/@([^>]+)>?/)&.[](1)&.strip&.downcase
      subject_pattern = order.original_email_subject.to_s.first(20)

      # ai_score 가 명시적으로 전달되지 않으면 order.rfq_confidence (high/medium/low/none) 에서 추정
      ai_score ||= score_from_confidence(order.try(:rfq_confidence))

      feedback = RfqFeedback.find_or_initialize_by(order: order, user: user)
      feedback.update!(
        verdict:         verdict,
        sender_domain:   domain,
        subject_pattern: subject_pattern,
        note:            note,
        ai_score:        ai_score
      )

      # Order rfq_status 업데이트
      new_rfq_status = case verdict
                       when "confirmed" then :rfq_triage
                       when "reverted"  then :rfq_pending
                       else :rfq_excluded
                       end
      order.update_column(:rfq_status, Order.rfq_statuses[new_rfq_status])

      feedback
    end

    # few-shot 예시 반환 (LLM 프롬프트 주입용)
    # 사용자 피드백 우선 → 부족하면 STATIC_EXAMPLES 로 보강해 항상 limit 만큼 반환
    def self.few_shot_examples(limit: 20)
      user_examples = RfqFeedback.includes(:order)
                                 .recent
                                 .limit(limit * 2)
                                 .map do |fb|
        {
          subject:  fb.order.original_email_subject.to_s.truncate(60),
          from:     fb.sender_domain.to_s,
          verdict:  fb.verdict,
          reason:   fb.note.presence || (fb.verdict == "confirmed" ? "사용자가 RFQ로 확인" : "사용자가 RFQ 아님으로 표시")
        }
      end

      combined = user_examples + STATIC_EXAMPLES
      combined.uniq { |e| [e[:subject], e[:from]] }.first(limit)
    end

    # rfq_confidence 문자열 → ai_score float 변환
    # high → 0.9, medium → 0.7, low → 0.4, none/nil → nil
    def self.score_from_confidence(confidence)
      case confidence.to_s.downcase
      when "high"   then 0.9
      when "medium" then 0.7
      when "low"    then 0.4
      else nil
      end
    end

    # Phase E: 학습 통계 집계
    # 반환:
    #   total: 전체 피드백 수
    #   with_score: ai_score 가 기록된 피드백 수
    #   ai_correct: AI 판정과 사용자 verdict 가 일치한 건수
    #   accuracy_pct: 정확도 (%)
    #   match_rate_pct: 최근 7일 일치율 (%)
    #   avg_score: ai_score 평균 (0~1)
    #   confirmed_count, rejected_count: verdict 분포
    def self.accuracy_stats(window_days: 7)
      total = RfqFeedback.count
      scored = RfqFeedback.with_ai_score.to_a   # GROUP BY 후 .to_a 패턴 적용
      with_score_count = scored.size

      ai_correct_count = scored.count { |fb| fb.ai_correct? }
      accuracy_pct = with_score_count.zero? ? 0.0 : (ai_correct_count.to_f / with_score_count * 100).round(1)

      recent_window = RfqFeedback.with_ai_score.where("created_at >= ?", window_days.days.ago).to_a
      recent_correct = recent_window.count { |fb| fb.ai_correct? }
      match_rate_pct = recent_window.empty? ? 0.0 : (recent_correct.to_f / recent_window.size * 100).round(1)

      avg_score = with_score_count.zero? ? 0.0 : (scored.sum { |fb| fb.ai_score.to_f } / with_score_count).round(3)

      {
        total:           total,
        with_score:      with_score_count,
        ai_correct:      ai_correct_count,
        accuracy_pct:    accuracy_pct,
        match_rate_pct:  match_rate_pct,
        avg_score:       avg_score,
        confirmed_count: RfqFeedback.confirmed.count,
        rejected_count:  RfqFeedback.rejected.count,
        window_days:     window_days,
        few_shot_total:  STATIC_EXAMPLES.size + total
      }
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
