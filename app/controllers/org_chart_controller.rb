# frozen_string_literal: true

class OrgChartController < ApplicationController
  def index
    # 사이드바용: 국가 목록만 (얕은 includes — 회사/부서/직원 상세는 선택 국가에서만 로드)
    @countries = Country.by_sort.includes(:companies)
    @selected_country_code = params[:country].presence || @countries.first&.code
    @selected_country = @countries.find { |c| c.code == @selected_country_code }
    # 선택된 국가의 조직도만 깊은 preload (visas 포함)
    @companies = @selected_country&.companies&.active&.preload(departments: { employees: :visas }) || []

    # 통계 — 단일 쿼리들 (includes 체인과 무관)
    @stats = {
      countries: @countries.size,
      companies: Company.active.count,
      departments: Department.where(active: true).count,
      employees: Employee.active.count
    }
  end
end
