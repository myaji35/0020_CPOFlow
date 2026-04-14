# frozen_string_literal: true

# 매일 새벽 — due_date 변경·마감 임박·경과된 Order들의 card_status 재평가
class CardStatusAutoAssignJob < ApplicationJob
  queue_as :default

  def perform
    Order.where(card_status_manually_set_at: nil)
         .where.not(status: %i[get_grn give_up done])
         .find_each(batch_size: 200) do |order|
      target = CardStatus::AutoAssigner.call(order)
      next if order.card_status_id == target.id
      order.update_column(:card_status_id, target.id)
    end
  end
end
