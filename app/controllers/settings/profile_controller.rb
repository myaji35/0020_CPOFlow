module Settings
  class ProfileController < ApplicationController
    def update
      if current_user.update(profile_params)
        redirect_to settings_root_path, notice: t("settings.save_success")
      else
        redirect_to settings_root_path, alert: current_user.errors.full_messages.to_sentence
      end
    end

    def update_locale
      locale = params[:locale]
      if User::LOCALES.include?(locale)
        current_user.update!(locale: locale)
        I18n.locale = locale.to_sym
      end
      redirect_back fallback_location: root_path
    end

    def update_theme
      theme = params[:theme]
      if User::THEMES.include?(theme)
        current_user.update!(theme: theme)
      end
      redirect_back fallback_location: root_path
    end

    # ISS-230: PATCH /settings/notification_preferences
    # 사용자별 알림 타입 × 채널 on/off 설정
    def update_notification_preferences
      prefs = params[:preferences]&.permit!&.to_h || {}
      current_user.update!(notification_preferences: prefs)
      redirect_to settings_root_path, notice: "알림 설정이 저장되었습니다."
    end

    private

    def profile_params
      params.require(:user).permit(:name, :locale, :branch, :theme)
    end
  end
end
