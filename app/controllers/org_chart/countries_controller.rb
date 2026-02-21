# frozen_string_literal: true

module OrgChart
  class CountriesController < ApplicationController
    before_action :require_admin!
    before_action :set_country, only: %i[show edit update destroy]

    def index
      @countries = Country.by_sort
    end

    def show
      @companies = @country.companies.active.includes(:departments).by_name
    end

    def new
      @country = Country.new
    end

    def create
      @country = Country.new(country_params)
      if @country.save
        redirect_to org_chart_path, notice: "국가가 추가되었습니다."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @country.update(country_params)
        redirect_to org_chart_path, notice: "국가 정보가 수정되었습니다."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @country.destroy
      redirect_to org_chart_path, notice: "국가가 삭제되었습니다."
    end

    private

    def set_country
      @country = Country.find(params[:id])
    end

    def country_params
      params.require(:country).permit(:code, :name, :name_en, :region, :flag_emoji, :sort_order)
    end
  end
end
