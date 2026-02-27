module Settings
  class BaseController < ApplicationController
    def index
      @email_accounts = current_user.email_accounts
      @google_chat_webhook_url = AppSetting.google_chat_webhook_url
    end
  end
end
