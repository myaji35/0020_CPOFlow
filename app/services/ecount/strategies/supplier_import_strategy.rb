# frozen_string_literal: true

module Ecount
  module Strategies
    class SupplierImportStrategy
      def upsert(row)
        attrs = map_row(row)
        record = Supplier.find_or_initialize_by(ecount_code: attrs[:ecount_code])
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
        code = row[:ecount_code].presence || auto_code(row[:name])
        {
          ecount_code:   code,
          code:          row[:code].presence || code,
          name:          row[:name].to_s.strip,
          country:       row[:country].to_s.strip,
          contact_email: row[:contact_email].to_s.strip,
          contact_phone: row[:contact_phone].to_s.strip,
          notes:         row[:notes].to_s.strip,
          active:        parse_active(row[:active]),
        }
      end

      def parse_active(val)
        return true if val.nil?
        %w[y yes 1 true 사용].include?(val.to_s.downcase.strip)
      end

      def auto_code(name)
        "SP_#{name.to_s.parameterize.upcase.first(20)}_#{SecureRandom.hex(3).upcase}"
      end
    end
  end
end
