class RemoveDuplicateOrderLinkIndexes < ActiveRecord::Migration[8.1]
  def change
    # t.references :source, polymorphic: true 가 자동 생성한 중복 인덱스 제거
    # idx_order_links_source / idx_order_links_target 만 남기고 자동 생성 인덱스 삭제
    if index_exists?(:order_links, [:source_type, :source_id], name: "index_order_links_on_source")
      remove_index :order_links, name: "index_order_links_on_source"
    end
    if index_exists?(:order_links, [:target_type, :target_id], name: "index_order_links_on_target")
      remove_index :order_links, name: "index_order_links_on_target"
    end
  end
end
