class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    @user = User.from_omniauth(request.env["omniauth.auth"])

    # ISS-268: 직전에 생성된 레코드인지 판정 (Rails 7.1+ previously_new_record?)
    was_new_record = @user.respond_to?(:previously_new_record?) ? @user.previously_new_record? : false

    if @user.persisted?
      # ISS-268: 신규 OAuth 가입자 → admin에게 branch 배정 검토 Notification
      notify_admins_on_new_oauth_user(@user) if was_new_record
      sign_in_and_redirect @user, event: :authentication
      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
    else
      session["devise.google_data"] = request.env["omniauth.auth"].except("extra")
      redirect_to new_user_registration_url, alert: @user.errors.full_messages.join(", ")
    end
  end

  def failure
    redirect_to new_user_session_path, alert: "Google 로그인에 실패했습니다. 다시 시도해주세요."
  end

  private

  # ISS-268: 신규 OAuth 가입 시 관리자에게 branch 배정/역할 검토 요청
  def notify_admins_on_new_oauth_user(user)
    admins = User.where(role: :admin)
    admins.find_each do |admin|
      Notification.create!(
        user:              admin,
        notifiable:        user,
        notification_type: "new_oauth_user",
        title:             "신규 OAuth 가입: #{user.display_name}",
        body:              "#{user.email} — 추정 branch: #{user.branch.presence || '미확정'} / role: #{user.role}. 필요 시 재배정하세요."
      )
    rescue => e
      Rails.logger.warn "[ISS-268] admin 알림 실패 user=#{user.id}: #{e.class}: #{e.message}"
    end
  end
end
