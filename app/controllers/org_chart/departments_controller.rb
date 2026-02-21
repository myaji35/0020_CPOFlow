# frozen_string_literal: true

module OrgChart
  class DepartmentsController < ApplicationController
    before_action :require_manager!
    before_action :set_company
    before_action :set_department, only: %i[show edit update destroy]

    def show
      @employees = @department.employees.active.includes(:visas).by_name
    end

    def new
      @department = @company.departments.build
      @parent_departments = @company.departments.active.root_level.by_sort
    end

    def create
      @department = @company.departments.build(department_params)
      if @department.save
        redirect_to org_chart_company_path(@company), notice: "부서가 추가되었습니다."
      else
        @parent_departments = @company.departments.active.root_level.by_sort
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @parent_departments = @company.departments.active.root_level.where.not(id: @department.id).by_sort
    end

    def update
      if @department.update(department_params)
        redirect_to org_chart_company_path(@company), notice: "부서 정보가 수정되었습니다."
      else
        @parent_departments = @company.departments.active.root_level.where.not(id: @department.id).by_sort
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @department.destroy
      redirect_to org_chart_company_path(@company), notice: "부서가 삭제되었습니다."
    end

    private

    def set_company
      @company = Company.find(params[:company_id])
    end

    def set_department
      @department = @company.departments.find(params[:id])
    end

    def department_params
      params.require(:department).permit(:name, :code, :parent_id, :sort_order, :active)
    end
  end
end
