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

      order = Order.new(
        title:                  build_title,
        customer_name:          @detection[:customer_name].presence || "Unknown",
        description:            @email[:snippet],
        status:                 :inbox,
        priority:               infer_priority,
        due_date:               @detection[:due_date],
        source_email_id:        @email[:id],
        original_email_subject: @email[:subject],
        original_email_body:    @email[:body].to_s.truncate(10_000),
        original_email_from:    @email[:from],
        item_name:              @detection[:item_hints],
        tags:                   build_tags,
        user:                   @account.user
      )

      if order.save
        # Assign the account owner as default assignee
        Assignment.find_or_create_by!(order: order, user: @account.user)
        Activity.create!(
          order:  order,
          user:   @account.user,
          action: "auto_created_from_email"
        )
        Rails.logger.info "[EmailToOrder] Created order ##{order.id} from Gmail #{@email[:id]}"
        order
      else
        Rails.logger.warn "[EmailToOrder] Failed to create order: #{order.errors.full_messages}"
        nil
      end
    end

    private

    def build_title
      subject = @email[:subject].to_s.strip
      return "RFQ — #{subject}" if subject.present?
      "RFQ from #{@detection[:customer_name]}"
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
      tags = ["rfq", "auto-import"]
      tags << "sika" if @detection[:item_hints].present?
      tags << "urgent" if @detection[:score] >= 70
      tags.join(",")
    end
  end
end
