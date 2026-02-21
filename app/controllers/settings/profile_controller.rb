module Settings
  class ProfileController < ApplicationController
    def update
      if current_user.update(profile_params)
        redirect_to settings_root_path, notice: "Profile updated."
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

    private

    def profile_params
      params.require(:user).permit(:name, :locale, :branch)
    end
  end
end
