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
        redirect_to settings_root_path, notice: t("settings.gmail.connect_success")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      current_user.email_accounts.find(params[:id]).destroy
      redirect_to settings_root_path, notice: t("settings.gmail.disconnect_success")
    end

    def sync
      account = current_user.email_accounts.find(params[:id])
      EmailSyncJob.perform_later(account_id: account.id)
      redirect_to settings_root_path, notice: "동기화를 시작했습니다. 잠시 후 Inbox를 확인하세요."
    rescue ActiveRecord::RecordNotFound
      redirect_to settings_root_path, alert: "계정을 찾을 수 없습니다."
    end

    private

    def email_account_params
      params.require(:email_account).permit(:email)
    end
  end
end
