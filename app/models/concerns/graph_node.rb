# frozen_string_literal: true

# OrderLink polymorphic source/target을 양방향으로 traverse하는 API.
# Order, OrderQuote가 graph node 역할을 하기 위해 include.
module GraphNode
  extend ActiveSupport::Concern

  included do
    has_many :outgoing_links,
             as: :source,
             class_name: "OrderLink",
             dependent: :destroy
    has_many :incoming_links,
             as: :target,
             class_name: "OrderLink",
             dependent: :destroy
  end

  # 양방향 연결된 노드 반환 (source/target 합산, 중복 제거)
  def linked_nodes(relation: nil, status: "confirmed")
    out = outgoing_links.where(status: status)
    inc = incoming_links.where(status: status)
    if relation
      out = out.where(relation: relation)
      inc = inc.where(relation: relation)
    end
    (out.map(&:target) + inc.map(&:source)).uniq
  end
end
