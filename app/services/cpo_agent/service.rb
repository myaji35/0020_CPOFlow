# frozen_string_literal: true

module CpoAgent
  class Service
    ANALYZERS = [
      PriceComparisonAnalyzer,
      SupplierRiskAnalyzer,
      DueDateRiskAnalyzer,
      CostSavingAnalyzer
    ].freeze

    def self.analyze(order)
      new(order).analyze
    end

    def initialize(order)
      @order = order
    end

    def analyze
      insights = []
      ANALYZERS.each do |analyzer_class|
        result = analyzer_class.new(@order).call
        insights << result if result
      rescue => e
        Rails.logger.warn "[CpoAgent] #{analyzer_class}: #{e.message}"
      end
      insights.compact
    end
  end
end
