class AddLastSeenAtToUsers < ActiveRecord::Migration[8.1]
  # 직원 목록의 '접속중'/'이용중' 배지용. ApplicationController#touch_last_seen이
  # 1분 throttle로 갱신. 5분 이내=online, 30분 이내=recently active.
  def change
    add_column :users, :last_seen_at, :datetime
    add_index  :users, :last_seen_at
  end
end
