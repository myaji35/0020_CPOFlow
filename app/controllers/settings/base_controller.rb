module Settings
  class BaseController < ApplicationController
    def index
      @email_accounts = current_user.email_accounts
    end
  end
end
