class Users::RegistrationsController < Devise::RegistrationsController
  layout "auth"

  private

  def sign_up_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :locale, :branch, :company_name)
  end

  def account_update_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :current_password, :locale, :branch, :company_name)
  end
end
