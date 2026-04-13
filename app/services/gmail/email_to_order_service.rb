# frozen_string_literal: true

module Gmail
  # Converts a detected RFQ email into an Order (kanban card).
  # Skips if Order with same source_email_id already exists.
  #
  # Usage:
  #   Gmail::EmailToOrderService.new(email_account, parsed_email, detection).create_order!
  class EmailToOrderService
    def initialize(email_account, parsed_email, detection_result, v2_result: nil, v2_log_id: nil, has_rfq_number: false)
      @account        = email_account
      @email          = parsed_email
      @detection      = detection_result
      @v2             = v2_result
      @v2_log_id      = v2_log_id
      @has_rfq_number = has_rfq_number
    end

    def create_order!
      # Idempotency: skip if already imported
      return nil if Order.exists?(source_email_id: @email[:id])

      # RFQ 번호가 있는 메일 → 바로 rfq_triage (견적 확정, 칸반 진입)
      # AI confirmed → rfq_triage
      # AI uncertain 또는 판정 없음 → rfq_pending (사용자 리뷰 대기)
      rfq_status_val = if @has_rfq_number
        Order.rfq_statuses[:rfq_triage]
      elsif @v2&.verdict == :confirmed || @detection[:rfq_verdict] == :confirmed
        Order.rfq_statuses[:rfq_triage]
      else
        Order.rfq_statuses[:rfq_pending]
      end

      # 발주번호 추출 + 메인 카드 탐색
      ref_no = ReferenceNumberExtractor.extract(
        @email[:subject].to_s,
        @email[:body].to_s
      )
      parent = find_parent_order(ref_no)

      order = Order.new(
        title:                  build_title,
        customer_name:          @detection[:customer_name].presence || "Unknown",
        description:            build_description,
        status:                 :new_rfq,
        rfq_status:             rfq_status_val,
        priority:               infer_priority,
        due_date:               @detection[:due_date],
        source_email_id:        @email[:id],
        gmail_thread_id:        @email[:thread_id],
        original_email_subject: @email[:subject],
        original_email_body:    @email[:body].to_s.truncate(10_000),
        original_email_html_body: @email[:html_body].to_s.truncate(100_000).presence,
        original_email_from:    @email[:from],
        item_name:              @detection[:item_hints],
        reference_no:           ref_no,
        rfq_no:                 ref_no,
        parent_order_id:        parent&.id,
        # LLM 추출 필드 전체 저장
        extracted_quantities:   @detection[:quantities]&.join(", "),
        extracted_project_name: @detection[:project_name],
        delivery_location:      @detection[:delivery_location],
        currency:               @detection[:currency],
        estimated_value:        @detection[:estimated_value],
        sender_domain:          extract_sender_domain,
        email_signature_json:   parse_email_signature,
        rfq_confidence:         @detection[:confidence],
        rfq_score:              @detection[:score],
        llm_analysis:           @detection[:llm_raw].to_json,
        llm_analyzed_at:        Time.current,
        tags:                   build_tags(ref_no),
        email_received_at:      @email[:date],
        user:                   @account.user,
        # Ariba 전용 필드
        source_type:            @detection[:is_ariba] ? :ariba : :email,
        ariba_event_url:        @detection[:is_ariba] ? extract_ariba_event_url : nil,
        ariba_event_id:         @detection[:ariba_event_id],
        # ISS-053 v2 분류 메트릭 (Shadow Mode)
        classifier_version:     @v2 ? "v2" : "v1",
        stage_reached:          @v2&.stage_reached,
        stage1_latency_ms:      nil, # stage별 latency 세분화는 Phase D
        stage2_latency_ms:      nil,
        stage3_latency_ms:      nil,
        classification_confidence: @v2 ? confidence_to_decimal(@v2.confidence) : nil,
        cache_hit:              @v2 ? (@v2.cache_hit || false) : false
      )

      if order.save
        # ISS-053 Shadow Mode: classification_logs back-link + would_exclude 플래그
        # ISS-056: 재시도/병렬 호출 시 동일 email_message_id로 여러 log row가 생성될 수 있음.
        #          Orchestrator가 방금 만든 특정 row(@v2_log_id)만 타겟팅하여 오염 방지.
        if @v2
          would_exclude_flag = (@v2.verdict == :excluded)
          begin
            if @v2_log_id
              ClassificationLog.where(id: @v2_log_id)
                               .update_all(order_id: order.id, would_exclude: would_exclude_flag)
            else
              # Fallback: Orchestrator 실패 등으로 log_id 없을 때 기존 동작 유지 (방어적)
              Rails.logger.warn "[EmailToOrder] v2_log_id missing — falling back to email_message_id scan"
              ClassificationLog.where(email_message_id: @email[:id])
                               .where(order_id: nil)
                               .update_all(order_id: order.id, would_exclude: would_exclude_flag)
            end
          rescue => e
            Rails.logger.warn "[EmailToOrder] ClassificationLog back-link failed: #{e.message}"
          end
        end

        if parent
          # 서브 카드: 메인 카드에 Activity 추가 (담당자 배정/초안 생성 스킵)
          Activity.create!(
            order:  parent,
            user:   @account.user,
            action: "thread_email_received"
          )
          update_contact_person_last_contacted(order)
          Rails.logger.info "[EmailToOrder] Sub-order ##{order.id} linked to parent ##{parent.id} (ref: #{ref_no})"
        else
          # 메인 카드: 기존 로직 동일
          Assignment.find_or_create_by!(order: order, user: @account.user)
          auto_assign_from_history(order)
          update_contact_person_last_contacted(order)
          Activity.create!(order: order, user: @account.user, action: "auto_created_from_email")
          Rails.logger.info "[EmailToOrder] Created order ##{order.id} score=#{@detection[:score]} from Gmail #{@email[:id]}"
        end

        order
      else
        Rails.logger.warn "[EmailToOrder] Failed to create order: #{order.errors.full_messages}"
        nil
      end
    end

    private

    # ISS-053: v2 confidence("high"/"medium"/"low"/"none") → decimal(0..1)
    # ClassificationOrchestrator private 메서드와 동일한 스케일.
    def confidence_to_decimal(conf)
      case conf.to_s
      when "high"   then 0.95
      when "medium" then 0.75
      when "low"    then 0.40
      else               0.0
      end
    end

    def build_title
      subject = @email[:subject].to_s.strip
      # RE/FW/Fwd 접두사 반복 제거
      subject = subject.sub(/\A\s*(RE|FW|Fwd)\s*:\s*/i, "").strip while subject.match?(/\A\s*(RE|FW|Fwd)\s*:/i)
      if @detection[:is_ariba]
        event_id = @detection[:ariba_event_id]
        if event_id.present?
          # 제목에서 일련번호 제거 (중복 방지) + "Event" 접두사 정리
          clean = subject.gsub(/\bEvent\s*/i, "").gsub(/\b#{Regexp.escape(event_id)}\b\s*[-–—]?\s*/, "").strip
          clean = clean.gsub(/\A[-–—\s]+|[-–—\s]+\z/, "").strip
          return clean.present? ? clean : "Ariba Event from #{@detection[:customer_name]}"
        end
        return subject if subject.present?
        return "Ariba RFQ from #{@detection[:customer_name]}"
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

    def build_tags(ref_no = nil)
      tags = [ "rfq", "auto-import" ]
      tags << "ariba" if @detection[:is_ariba]
      tags << "sika" if @detection[:item_hints].present?
      tags << "urgent" if @detection[:score] >= 70
      tags.join(",")
    end

    # 동일 건 메인 카드(parent_order_id: nil) 탐색
    # 1순위: reference_no 기반, 2순위: gmail_thread_id 기반 fallback
    def find_parent_order(ref_no)
      # 1순위: reference_no 기반
      if ref_no.present?
        base = Order.where(reference_no: ref_no).where(parent_order_id: nil)
        found = base.where.not(status: :new_rfq).order(created_at: :asc).first ||
                base.order(created_at: :asc).first
        return found if found
      end

      # 2순위: gmail_thread_id 기반 fallback
      thread_id = @email[:thread_id]
      return nil if thread_id.blank?

      Order.where(gmail_thread_id: thread_id)
           .where(parent_order_id: nil)
           .order(created_at: :asc)
           .first
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

    # 이메일 발신자와 매칭되는 ContactPerson의 last_contacted_at 자동 업데이트
    # 매칭되는 담당자가 없으면 서명 기반으로 자동 생성
    def update_contact_person_last_contacted(order)
      from_raw = @email[:from].to_s
      sender_email = from_raw.match(/<(.+?)>/)&.[](1) || from_raw.strip.downcase
      return if sender_email.blank?

      cp = ContactPerson.find_by("LOWER(email) = ?", sender_email.downcase)

      if cp
        cp.update_column(:last_contacted_at, Time.current)
      else
        auto_create_contact_person(order, sender_email)
      end
    rescue => e
      Rails.logger.warn "[EmailToOrder] ContactPerson update failed: #{e.message}"
    end

    # 이메일 서명에서 담당자 자동 생성
    def auto_create_contact_person(order, sender_email)
      domain = extract_sender_domain
      return if domain.blank?

      contactable = find_contactable_by_domain(domain)
      return unless contactable

      sig = order.email_signature_json.present? ? JSON.parse(order.email_signature_json) : {}
      return if sig.blank? && sender_email.blank?

      # 동일 이메일 중복 방지
      existing = contactable.contact_persons.find_by("LOWER(email) = ?", (sig["email"].presence || sender_email).downcase)
      if existing
        existing.update_column(:last_contacted_at, Time.current)
        return
      end

      cp = contactable.contact_persons.create(
        name:              sig["name"].presence || sender_email.split("@").first.humanize,
        email:             sig["email"].presence || sender_email,
        title:             sig["title"],
        phone:             sig["phone"],
        mobile:            sig["mobile"],
        source:            "email_signature",
        last_contacted_at: Time.current
      )

      if cp.persisted?
        Rails.logger.info "[EmailToOrder] Auto-created ContactPerson '#{cp.name}' for #{contactable.class.name}##{contactable.id} (#{contactable.name})"
      else
        Rails.logger.warn "[EmailToOrder] Failed to create ContactPerson: #{cp.errors.full_messages.join(', ')}"
      end
    end

    # sender_domain으로 Client 또는 Supplier 검색
    def find_contactable_by_domain(domain)
      return nil if domain.blank?
      Client.find_by("website LIKE ?", "%#{domain}%") ||
        Supplier.find_by("website LIKE ? OR contact_email LIKE ?", "%#{domain}%", "%#{domain}%")
    end

    # 이메일 서명 파싱 → JSON 문자열로 저장
    def parse_email_signature
      result = EmailSignatureParserService.parse(
        @email[:body],
        @email[:html_body]
      )
      result.present? ? result.to_json : nil
    rescue => e
      Rails.logger.warn "[EmailToOrder] Signature parse failed: #{e.message}"
      nil
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
        Assignment.find_or_create_by!(order: order, employee: assignee)
        Rails.logger.info "[EmailToOrder] Auto-assigned #{assignee.display_name} from domain history"
      end
    end
  end
end
