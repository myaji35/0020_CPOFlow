# frozen_string_literal: true

module Employees
  # 직원 폼 내 부서 인라인 관리 (AJAX)
  # GET    /employees/departments        → 전체 부서 목록 (JSON)
  # POST   /employees/departments        → 부서 추가
  # DELETE /employees/departments/:id   → 부서 삭제
  class DepartmentsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_manager!

    def index
      departments = Department.active.by_sort.includes(:company)
      render json: departments.map { |d|
        { id: d.id, name: d.full_name, company: d.company.name, employee_count: d.employee_count }
      }
    end

    def create
      company = Company.find_by(id: params[:company_id]) || Company.first
      department = company.departments.build(name: params[:name].to_s.strip, active: true)

      if department.name.blank?
        return render json: { error: "부서명을 입력해주세요." }, status: :unprocessable_entity
      end

      if department.save
        render json: {
          id:   department.id,
          name: department.full_name,
          company: company.name,
          employee_count: 0
        }, status: :created
      else
        render json: { error: department.errors.full_messages.first }, status: :unprocessable_entity
      end
    end

    def destroy
      department = Department.find(params[:id])

      if department.employee_count > 0
        return render json: {
          error: "소속 직원이 #{department.employee_count}명 있어 삭제할 수 없습니다. 직원을 먼저 이동해주세요."
        }, status: :unprocessable_entity
      end

      department.destroy
      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "부서를 찾을 수 없습니다." }, status: :not_found
    end
  end
end
