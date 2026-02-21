# frozen_string_literal: true

module Ecount
  module Strategies
    class OrderImportStrategy
      # eCount 상태 → CPOFlow Kanban 매핑
      STATUS_MAP = {
        "견적요청" => "inbox",
        "검토중"   => "reviewing",
        "견적발송" => "quoted",
        "발주확정" => "confirmed",
        "조달중"   => "procuring",
        "품질검사" => "qa",
        "납품완료" => "delivered",
      }.freeze

      def initialize(user)
        @user = user
      end

      def upsert(row)
        attrs = map_row(row)
        # ecount_ prefix로 source_email_id 사용 (중복 방지)
        record = Order.find_or_initialize_by(source_email_id: attrs[:source_email_id])
        record.assign_attributes(attrs)
        record.save!
        { ok: true }
      rescue ActiveRecord::RecordInvalid => e
        { ok: false, error: e.message }
      rescue => e
        { ok: false, error: "#{e.class}: #{e.message}" }
      end

      private

      def map_row(row)
        ref      = row[:source_ref].presence || "ecount_#{SecureRandom.hex(6)}"
        status   = STATUS_MAP[row[:ecount_status].to_s.strip] || "inbox"
        due      = parse_date(row[:due_date])

        {
          source_email_id:        "ecount_#{ref}",
          title:                  "#{row[:name] || row[:ecount_code] || ref}",
          customer_name:          row[:customer_name].presence || "eCount Import",
          description:            "eCountERP 거래이력 이관 (거래번호: #{ref})",
          status:                 status,
          priority:               infer_priority(due),
          due_date:               due,
          quantity:               row[:quantity].to_s.to_i,
          estimated_value:        row[:estimated_value].to_s.gsub(/[^\d.]/, "").to_f,
          currency:               row[:currency].presence || "USD",
          item_name:              row[:name].presence || row[:ecount_code],
          tags:                   "ecount-import",
          original_email_from:    "ecount@import",
          original_email_subject: "eCount 거래이력: #{ref}",
          user:                   @user,
        }
      end

      def parse_date(val)
        return nil if val.blank?
        Date.parse(val.to_s.strip)
      rescue Date::Error, ArgumentError
        nil
      end

      def infer_priority(due)
        return :medium unless due
        days = (due - Date.today).to_i
        if    days <= 7  then :urgent
        elsif days <= 14 then :high
        elsif days <= 30 then :medium
        else                  :low
        end
      end
    end
  end
end
