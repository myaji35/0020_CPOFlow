class BackfillOrdersCardStatus < ActiveRecord::Migration[8.1]
  def up
    # 반드시 seed 먼저 실행됐다고 가정 (프로덕션에서 rails db:seed 후 rails db:migrate 순서)
    # 방어적으로 여기서도 7개 프리셋이 있는지 확인하고 없으면 로드
    if CardStatus.count < 7
      load Rails.root.join("db/seeds/card_statuses.rb")
    end

    mapping = {
      "urgent" => CardStatus.find_by!(key: "urgent").id,
      "high"   => CardStatus.find_by!(key: "high").id,
      "medium" => CardStatus.find_by!(key: "normal").id,
      "low"    => CardStatus.find_by!(key: "low").id
    }

    mapping.each do |legacy, new_id|
      execute "UPDATE orders SET card_status_id = #{new_id} WHERE priority = #{priority_value(legacy)} AND card_status_id IS NULL"
    end

    # 그래도 남은 것은 default(normal)로
    normal_id = CardStatus.find_by!(key: "normal").id
    execute "UPDATE orders SET card_status_id = #{normal_id} WHERE card_status_id IS NULL"
  end

  def down
    execute "UPDATE orders SET card_status_id = NULL"
  end

  private

  def priority_value(key)
    { "low" => 0, "medium" => 1, "high" => 2, "urgent" => 3 }[key]
  end
end
