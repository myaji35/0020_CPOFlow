# frozen_string_literal: true

class CardStatus
  class AutoAssigner
    def self.call(order)
      candidates = CardStatus.where.not(auto_rule: nil).order(auto_priority: :desc)
      match = candidates.find { |cs| cs.auto_applies_to?(order) }
      match || CardStatus.default
    end

    def self.for_due_date(due_date)
      call(Order.new(due_date: due_date))
    end
  end
end
