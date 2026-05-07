# frozen_string_literal: true

# 페르소나 전환 — admin 유저 전용 (kds@ 등 다중 역할 계정)
# POST /persona/:key → session[:persona] 변경 후 원래 페이지로 redirect
class PersonasController < ApplicationController
  before_action :require_admin_user

  def update
    key = params[:key].to_s
    if key.in?(PERSONAS.keys)
      session[:persona] = key
      flash[:notice] = "#{PERSONAS[key][:label]} 모드로 전환했습니다."
    end
    redirect_back fallback_location: root_path
  end

  private

  def require_admin_user
    redirect_to root_path, alert: "권한이 없습니다." unless current_user&.admin?
  end
end
