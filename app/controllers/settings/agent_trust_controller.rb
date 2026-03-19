# frozen_string_literal: true

module Settings
  class AgentTrustController < ApplicationController
    def toggle
      level = AgentTrustLevel.find_or_create_by(
        user: current_user,
        insight_type: params[:insight_type]
      )
      level.update!(auto_mode: !level.auto_mode)

      redirect_to settings_root_path, notice: "#{params[:insight_type]} 자동 모드가 #{level.auto_mode ? '활성화' : '비활성화'}되었습니다"
    end
  end
end
