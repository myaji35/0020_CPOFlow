# frozen_string_literal: true

# Placeholder — 본 구현은 T7/T12/T13 단계에서 추가됨.
class OrderQuoteItemsController < ApplicationController
  before_action :authenticate_user!

  def index
    head :no_content
  end

  def create
    head :no_content
  end

  def update
    head :no_content
  end

  def destroy
    head :no_content
  end
end
