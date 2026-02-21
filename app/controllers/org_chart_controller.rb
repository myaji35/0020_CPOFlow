# frozen_string_literal: true

class OrgChartController < ApplicationController
  def index
    @countries = Country.by_sort.includes(companies: { departments: :employees })
    @selected_country_code = params[:country].presence || @countries.first&.code
    @selected_country = @countries.find { |c| c.code == @selected_country_code }
    @companies = @selected_country&.companies&.active&.includes(departments: { employees: :visas }) || []
  end
end
