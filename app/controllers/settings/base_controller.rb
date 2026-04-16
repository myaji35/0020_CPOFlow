module Settings
  class BaseController < ApplicationController
    def index
      @email_accounts = current_user.email_accounts
      @google_chat_webhook_url = AppSetting.google_chat_webhook_url
      @gmail_connected_count = @email_accounts.select(&:connected?).count
      @boards_count = KanbanBoard.count rescue 0
    end
  end
end
