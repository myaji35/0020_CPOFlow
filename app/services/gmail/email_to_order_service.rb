# frozen_string_literal: true

module Gmail
  # Converts a detected RFQ email into an Order (kanban card).
  # Skips if Order with same source_email_id already exists.
  #
  # Usage:
  #   Gmail::EmailToOrderService.new(email_account, parsed_email, detection).create_order!
  class EmailToOrderService
    def initialize(email_account, parsed_email, detection_result)
      @account   = email_account
      @email     = parsed_email
      @detection = detection_result
    end

    def create_order!
      # Idempotency: skip if already imported
      return nil if Order.exists?(source_email_id: @email[:id])

      verdict = @detection[:rfq_verdict] || :confirmed
      rfq_status_val = case verdict
      when :confirmed  then Order.rfq_statuses[:rfq_confirmed]
      when :uncertain  then Order.rfq_statuses[:rfq_uncertain]
      else                  Order.rfq_statuses[:rfq_excluded]
      end

      order = Order.new(
        title:                  build_title,
        customer_name:          @detection[:customer_name].presence || "Unknown",
        description:            build_description,
        status:                 :inbox,
        rfq_status:             rfq_status_val,
        priority:               infer_priority,
        due_date:               @detection[:due_date],
        source_email_id:        @email[:id],
        original_email_subject: @email[:subject],
        original_email_body:    @email[:body].to_s.truncate(10_000),
        original_email_html_body: @email[:html_body].to_s.truncate(100_000).presence,
        original_email_from:    @email[:from],
        item_name:              @detection[:item_hints],
        # LLM 추출 필드 전체 저장
        extracted_quantities:   @detection[:quantities]&.join(", "),
        extracted_project_name: @detection[:project_name],
        delivery_location:      @detection[:delivery_location],
        currency:               @detection[:currency],
        estimated_value:        @detection[:estimated_value],
        sender_domain:          extract_sender_domain,
        rfq_confidence:         @detection[:confidence],
        rfq_score:              @detection[:score],
        llm_analysis:           @detection[:llm_raw].to_json,
        llm_analyzed_at:        Time.current,
        tags:                   build_tags,
        user:                   @account.user,
        # Ariba 전용 필드
        source_type:            @detection[:is_ariba] ? :ariba : :email,
        ariba_event_url:        @detection[:is_ariba] ? extract_ariba_event_url : nil,
        ariba_event_id:         @detection[:ariba_event_id]
      )

      if order.save
        # 기본 담당자: 계정 소유자
        Assignment.find_or_create_by!(order: order, user: @account.user)

        # Phase E: 발주처 이력 기반 담당자 자동 배정
        auto_assign_from_history(order)

        Activity.create!(
          order:  order,
          user:   @account.user,
          action: "auto_created_from_email"
        )

        # confirmed 판정 시에만 답변 초안 자동 생성 (non-RFQ 메일은 스킵)
        if verdict == :confirmed && @detection[:is_rfq]
          RfqReplyDraftJob.perform_later(order.id)
        end

        Rails.logger.info "[EmailToOrder] Created order ##{order.id} verdict=#{verdict} from Gmail #{@email[:id]}"
        order
      else
        Rails.logger.warn "[EmailToOrder] Failed to create order: #{order.errors.full_messages}"
        nil
      end
    end

    private

    def build_title
      subject = @email[:subject].to_s.strip
      if @detection[:is_ariba]
        event_id = @detection[:ariba_event_id]
        return "[ARIBA] #{event_id} - #{subject}" if event_id.present?
        return "[ARIBA] #{subject}" if subject.present?
        return "[ARIBA] RFQ from #{@detection[:customer_name]}"
      end
      # RFQ: "RFQ — 제목" 형식, non-RFQ: 제목 그대로 표시
      return subject if subject.present? && !@detection[:is_rfq]
      return "RFQ — #{subject}" if subject.present?
      "RFQ from #{@detection[:customer_name]}"
    end

    def build_description
      parts = [ @email[:snippet] ]
      parts << "프로젝트: #{@detection[:project_name]}" if @detection[:project_name].present?
      parts << "수량: #{@detection[:quantities].join(", ")}" if @detection[:quantities]&.any?
      parts.compact.join("\n")
    end

    def infer_priority
      due = @detection[:due_date]
      return :medium unless due

      days = (due - Date.today).to_i
      if    days <= 7  then :urgent
      elsif days <= 14 then :high
      elsif days <= 30 then :medium
      else                  :low
      end
    end

    def build_tags
      tags = [ "rfq", "auto-import" ]
      tags << "ariba" if @detection[:is_ariba]
      tags << "sika" if @detection[:item_hints].present?
      tags << "urgent" if @detection[:score] >= 70
      tags.join(",")
    end

    def extract_sender_domain
      @email[:from].to_s.match(/@([^>]+)>?/)&.[](1)&.strip&.downcase
    end

    # Ariba 포털 이벤트 링크 추출: HTML body → plain body 순으로 탐색
    def extract_ariba_event_url
      ariba_url_pattern = /(https?:\/\/[^\s<>"']*ariba\.com[^\s<>"']*)/i
      combined = @email[:html_body].to_s + " " + @email[:body].to_s
      match = combined.match(ariba_url_pattern)
      match ? match[1].strip : nil
    end

    # Phase E: 같은 발주처(이메일 도메인) 최근 Order 담당자를 자동 배정
    def auto_assign_from_history(order)
      domain = extract_sender_domain
      return if domain.blank?

      last_order = Order.where("original_email_from LIKE ?", "%#{domain}%")
                        .where.not(id: order.id)
                        .joins(:assignments)
                        .order(created_at: :desc)
                        .first
      return unless last_order

      last_order.assignees.each do |assignee|
        next if assignee == @account.user  # 이미 기본 배정된 경우 스킵
        Assignment.find_or_create_by!(order: order, user: assignee)
        Rails.logger.info "[EmailToOrder] Auto-assigned #{assignee.email} from domain history"
      end
    end
  end
end
