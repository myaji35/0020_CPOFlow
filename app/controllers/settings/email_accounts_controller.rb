module Settings
  class EmailAccountsController < ApplicationController
    def index
      @email_accounts = current_user.email_accounts
    end

    def new
      @email_account = current_user.email_accounts.build
    end

    def create
      @email_account = current_user.email_accounts.build(email_account_params)
      if @email_account.save
        redirect_to settings_root_path, notice: "Email account connected."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      current_user.email_accounts.find(params[:id]).destroy
      redirect_to settings_root_path, notice: "Email account removed."
    end

    private

    def email_account_params
      params.require(:email_account).permit(:email)
    end
  end
end
