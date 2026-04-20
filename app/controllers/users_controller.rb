# frozen_string_literal: true

class UsersController < ApplicationController
  # GET /users/mention_suggestions?q=검색어
  # 1) Employee.active + user_id 매핑된 레코드 우선
  # 2) 부족하면 User 테이블에서 보충 (Employee 미등록된 관리자 계정 포함 보장)
  def mention_suggestions
    q = params[:q].to_s.strip
    like = "%#{q}%"

    employees = Employee.active
                        .where.not(user_id: nil)
                        .where("LOWER(name) LIKE LOWER(?)", like)
                        .order(:name)
                        .limit(8)

    items = employees.map { |e|
      {
        id:           e.user_id,
        employee_id:  e.id,
        display_name: e.display_name,
        initials:     e.initials,
        branch:       e.nationality.to_s,
        job_title:    e.job_title.to_s,
        source:       "employee"
      }
    }

    # User 보충 — 이미 포함된 user_id 는 제외, 최대 8명까지
    if items.size < 8
      taken_user_ids = items.map { |i| i[:id] }.compact
      remaining      = 8 - items.size
      users = User.where("LOWER(name) LIKE LOWER(?) OR LOWER(email) LIKE LOWER(?)", like, like)
                  .where.not(id: taken_user_ids)
                  .order(:name)
                  .limit(remaining)

      items.concat(users.map { |u|
        {
          id:           u.id,
          employee_id:  nil,
          display_name: u.display_name,
          initials:     u.initials,
          branch:       (u.respond_to?(:branch) ? u.branch.to_s : ""),
          job_title:    "",
          source:       "user"
        }
      })
    end

    render json: items
  end
end
