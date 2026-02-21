# frozen_string_literal: true

module OrgChart
  class CompaniesController < ApplicationController
    before_action :require_manager!
    before_action :set_company, only: %i[show edit update destroy]

    def index
      @companies = Company.active.includes(:country, :departments).by_name
    end

    def show
      @departments = @company.departments.active.root_level
                             .includes(:sub_departments, :employees).by_sort
    end

    def new
      @company = Company.new
      @countries = Country.by_sort
    end

    def create
      @company = Company.new(company_params)
      if @company.save
        redirect_to org_chart_path, notice: "법인이 추가되었습니다."
      else
        @countries = Country.by_sort
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @countries = Country.by_sort
    end

    def update
      if @company.update(company_params)
        redirect_to org_chart_company_path(@company), notice: "법인 정보가 수정되었습니다."
      else
        @countries = Country.by_sort
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @company.destroy
      redirect_to org_chart_path, notice: "법인이 삭제되었습니다."
    end

    private

    def set_company
      @company = Company.find(params[:id])
    end

    def company_params
      params.require(:company).permit(
        :country_id, :name, :name_en, :company_type,
        :registration_number, :address, :active
      )
    end
  end
end
