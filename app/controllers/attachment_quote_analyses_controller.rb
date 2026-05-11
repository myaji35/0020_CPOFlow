# frozen_string_literal: true

# Placeholder — 본 구현은 T11 단계에서 추가됨.
class AttachmentQuoteAnalysesController < ApplicationController
  before_action :authenticate_user!

  def create
    head :no_content
  end

  def reanalyze
    head :no_content
  end
end
