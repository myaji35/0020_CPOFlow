# frozen_string_literal: true

class UsersController < ApplicationController
  # GET /users/mention_suggestions?q=검색어
  def mention_suggestions
    q = params[:q].to_s.strip
    employees = Employee.active
                        .where.not(user_id: nil)
                        .where("LOWER(name) LIKE LOWER(?)", "%#{q}%")
                        .order(:name)
                        .limit(8)

    render json: employees.map { |e|
      {
        id:           e.user_id,
        employee_id:  e.id,
        display_name: e.display_name,
        initials:     e.initials,
        branch:       e.branch.presence || "",
        job_title:    e.job_title.presence || ""
      }
    }
  end
end
