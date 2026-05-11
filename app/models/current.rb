# ISS-303: 모델 레벨에서 current_user 접근용 CurrentAttributes.
# ApplicationController가 before_action으로 Current.user = current_user 세팅하면,
# 모델 콜백(Auditable concern)이 누가 변경했는지 기록할 수 있다.
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
