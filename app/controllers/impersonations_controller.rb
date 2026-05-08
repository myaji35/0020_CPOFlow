# frozen_string_literal: true

# ISS-352: 직원 Impersonation
# POST /impersonations       → 토큰 발급 (admin 전용)
# GET  /impersonations/enter → 토큰으로 가장 진입 (새 탭)
# DELETE /impersonations     → 가장 해제, admin으로 복귀
class ImpersonationsController < ApplicationController
  before_action :require_admin!, only: [ :create ]

  # POST /impersonations — 토큰 발급 후 새 탭 URL 반환
  def create
    target = User.find(params[:user_id])

    if target.admin?
      return redirect_back fallback_location: employees_path,
                           alert: "Admin 계정은 가장할 수 없습니다."
    end

    token = ImpersonationToken.issue!(admin: current_user, target_user: target)
    redirect_to impersonations_enter_path(token: token.token),
                allow_other_host: false,
                status: :see_other
  end

  # GET /impersonations/enter?token=xxx — 토큰 검증 후 세션 세팅
  def enter
    record = ImpersonationToken.valid.find_by(token: params[:token])

    unless record
      return redirect_to root_path, alert: "유효하지 않거나 만료된 링크입니다."
    end

    record.consume!
    session[:impersonating_user_id] = record.target_user_id
    session[:impersonator_id]       = record.admin_id

    redirect_to root_path, notice: "#{record.target_user.display_name} 계정으로 보는 중입니다."
  end

  # DELETE /impersonations — 가장 해제
  def destroy
    session.delete(:impersonating_user_id)
    session.delete(:impersonator_id)
    redirect_to employees_path, notice: "내 계정으로 돌아왔습니다."
  end

  private

  def require_admin!
    redirect_to root_path, alert: "권한이 없습니다." unless current_real_user&.admin?
  end
end
