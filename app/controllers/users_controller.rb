# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :require_admin!, only: %i[search]

  # GET /users/search?q=&exclude_linked=1
  # admin 전용 — 직원 폼 email 자동완성용. 미연결(어떤 employee와도 연결 안 된) User 우선.
  def search
    q = params[:q].to_s.strip
    linked_user_ids = Employee.where.not(user_id: nil).pluck(:user_id).uniq

    base = User.all
    base = base.where("LOWER(name) LIKE :t OR LOWER(email) LIKE :t", t: "%#{q.downcase}%") if q.present?

    # 미연결 우선 정렬 (CASE WHEN), 같은 그룹 내에서는 이름순
    sql = sanitize_sql_array([
      "CASE WHEN id IN (?) THEN 1 ELSE 0 END, name",
      linked_user_ids.empty? ? [ -1 ] : linked_user_ids
    ])
    base = base.order(Arel.sql(sql)).limit(20)

    results = base.map do |u|
      linked = linked_user_ids.include?(u.id)
      {
        id:     u.id,
        name:   u.email,                                    # input 표시용 (email 기반 매칭)
        code:   "#{u.display_name}#{linked ? ' · 연결됨' : ''}",
        linked: linked
      }
    end
    render json: results
  end

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
      # CEO 페르소나로 전환한 사용자는 멘션에서 "(CEO)" 라벨로 표시
      is_self        = e.user_id == current_user.id
      persona_suffix = (is_self && ceo_mode?) ? " (CEO)" : ""
      {
        id:           e.user_id,
        employee_id:  e.id,
        display_name: e.display_name + persona_suffix,
        initials:     e.initials,
        branch:       e.nationality.to_s,
        job_title:    ceo_mode? && is_self ? "CEO" : e.job_title.to_s,
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

  private

  def require_admin!
    return if current_user&.admin?
    render json: { error: "Admin only" }, status: :forbidden
  end

  def sanitize_sql_array(arr)
    ActiveRecord::Base.send(:sanitize_sql_array, arr)
  end
end
