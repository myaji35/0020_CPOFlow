# frozen_string_literal: true

module Employees
  # 직원 폼 내 직책 인라인 관리 (AJAX)
  # GET    /employees/job_titles        → 전체 직책 목록 (JSON)
  # POST   /employees/job_titles        → 직책 추가
  # DELETE /employees/job_titles/:id    → 직책 삭제
  class JobTitlesController < ApplicationController
    before_action :authenticate_user!
    before_action :require_manager!

    def index
      job_titles = JobTitle.active.by_sort
      render json: job_titles.map { |jt|
        { id: jt.id, name: jt.name, employee_count: jt.employee_count }
      }
    end

    def create
      name = params[:name].to_s.strip

      if name.blank?
        return render json: { error: "직책명을 입력해주세요." }, status: :unprocessable_entity
      end

      job_title = JobTitle.new(name: name, active: true, sort_order: JobTitle.count)

      if job_title.save
        render json: { id: job_title.id, name: job_title.name, employee_count: 0 }, status: :created
      else
        render json: { error: job_title.errors.full_messages.first }, status: :unprocessable_entity
      end
    end

    def destroy
      job_title = JobTitle.find(params[:id])

      if job_title.employee_count > 0
        return render json: {
          error: "해당 직책의 직원이 #{job_title.employee_count}명 있어 삭제할 수 없습니다."
        }, status: :unprocessable_entity
      end

      job_title.destroy
      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "직책을 찾을 수 없습니다." }, status: :not_found
    end
  end
end
