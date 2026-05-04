# AtoZ 직원 등록 대기 안내 페이지
# Employee 매칭 안 된 사용자(active=false)가 보는 유일한 화면.
# ApplicationController#enforce_active_account 가드를 우회하기 위해 active 사용자 체크 skip.
class Users::PendingController < ApplicationController
  skip_before_action :enforce_active_account

  def show
    # active 사용자가 실수로 들어오면 dashboard로 보냄
    redirect_to authenticated_root_path and return if current_user&.active?
  end
end
