class OrderLink < ApplicationRecord
  RELATIONS = %w[derived_from quoted_as confirmed_to delivered_as references].freeze
  STATUSES  = %w[confirmed suggested rejected].freeze

  belongs_to :source, polymorphic: true
  belongs_to :target, polymorphic: true
  belongs_to :created_by, class_name: "User", optional: true

  serialize :metadata, coder: JSON

  validates :relation,   inclusion: { in: RELATIONS }
  validates :status,     inclusion: { in: STATUSES }
  validates :confidence, numericality: { in: 0.0..1.0 }

  scope :confirmed, -> { where(status: "confirmed") }
  scope :suggested, -> { where(status: "suggested") }
  scope :rejected,  -> { where(status: "rejected") }
  scope :for_node, ->(node) {
    where(source_type: node.class.name, source_id: node.id)
      .or(where(target_type: node.class.name, target_id: node.id))
  }
end
