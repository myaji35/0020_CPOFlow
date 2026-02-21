# frozen_string_literal: true

module Ecount
  module Strategies
    class ProductImportStrategy
      SITE_CATEGORIES = Product.site_categories.keys.freeze rescue %w[nuclear hydro tunnel gtx general]

      def upsert(row)
        attrs = map_row(row)
        record = Product.find_or_initialize_by(ecount_code: attrs[:ecount_code])
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
          ecount_code:  code,
          code:         row[:code].presence || code,
          name:         row[:name].to_s.strip,
          description:  row[:description].to_s.strip,
          unit:         row[:unit].presence || "EA",
          category:     row[:category].to_s.strip,
          brand:        row[:brand].to_s.strip,
          unit_price:   parse_decimal(row[:unit_price]),
          currency:     row[:currency].presence || "USD",
          sika_product: sika_brand?(row[:brand]),
          active:       parse_active(row[:active]),
        }
      end

      def parse_decimal(val)
        val.to_s.gsub(/[^\d.]/, "").to_f
      end

      def parse_active(val)
        return true if val.nil?
        %w[y yes 1 true 사용].include?(val.to_s.downcase.strip)
      end

      def sika_brand?(brand)
        brand.to_s.downcase.include?("sika")
      end

      def auto_code(name)
        "IMPORT_#{name.to_s.parameterize.upcase.first(20)}_#{SecureRandom.hex(3).upcase}"
      end
    end
  end
end
