# LegalController — Privacy Policy & Terms of Service
# Google OAuth Verification 필수 자료 (인증 없이 공개)
class LegalController < ApplicationController
  skip_before_action :authenticate_user!
  layout "legal"

  def privacy
  end

  def terms
  end
end
