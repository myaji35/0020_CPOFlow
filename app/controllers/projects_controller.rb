class ProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project, only: %i[show edit update destroy]
  # ISS-264: viewer read-only — CRUD는 member 이상만
  before_action :require_member!, only: %i[new create edit update]
  before_action :require_manager!, only: %i[destroy]
  # ISS-380: MenuPermission DB 2차 가드
  before_action -> { enforce_menu_permission!(:projects, :create) }, only: %i[new create]
  before_action -> { enforce_menu_permission!(:projects, :update) }, only: %i[edit update]
  before_action -> { enforce_menu_permission!(:projects, :delete) }, only: %i[destroy]

  def index
    @view = params[:view].presence_in(%w[list gantt]) || "list"
    @projects = Project.includes(:client, :orders).by_name
    @projects = @projects.where(site_category: params[:category]) if params[:category].present?
    @projects = @projects.where(status: params[:status]) if params[:status].present?
    @projects = @projects.where(client_id: params[:client_id]) if params[:client_id].present?
    # 검색 강화: 이름 + 위치 + 코드
    if params[:q].present?
      q = "%#{params[:q]}%"
      @projects = @projects.where("projects.name LIKE ? OR projects.location LIKE ? OR projects.code LIKE ?", q, q, q)
    end
    # 활성/비활성 필터
    @projects = @projects.active if params[:active_only] == "1"

    # FR-07: KPI 통계 카드 (4개)
    all_projects       = Project.includes(:orders).all
    @total_count       = all_projects.size
    @total_budget      = all_projects.sum { |p| p.budget.to_f }
    @total_utilized    = all_projects.sum(&:budget_utilized)
    @active_count      = Project.active.count
    @active_order_count = Order.joins(:project).where(projects: { status: :active }).count
    @avg_orders_per_project = @total_count > 0 ? (Order.where.not(project_id: nil).count.to_f / @total_count).round(1) : 0

    # ISS-226: Gantt 뷰 데이터
    if @view == "gantt"
      dated = @projects.to_a.select { |p| p.start_date && p.end_date }
      @gantt_range = if dated.any?
        { start: dated.map(&:start_date).min, end: dated.map(&:end_date).max }
      else
        { start: Date.today.beginning_of_year, end: Date.today.end_of_year }
      end
      @gantt_total_days = [ (@gantt_range[:end] - @gantt_range[:start]).to_i, 1 ].max
      @gantt_projects = dated.sort_by(&:start_date)
      @gantt_today = Date.today
    end
  end

  def show
    # FR-04: 관련 오더 탭 강화
    orders_scope = @project.orders
    case params[:period]
    when "this_month" then orders_scope = orders_scope.where(created_at: Time.current.beginning_of_month..)
    when "3months"    then orders_scope = orders_scope.where(created_at: 3.months.ago..)
    when "this_year"  then orders_scope = orders_scope.where(created_at: Time.current.beginning_of_year..)
    end

    @orders              = orders_scope.by_due_date.includes(:client, :supplier, :assignees).limit(20)
    @total_orders_count  = orders_scope.count
    @order_total_value   = @project.orders.sum(:estimated_value).to_f
    @order_status_counts = @project.orders.group(:status).count
  end

  def new
    @project = Project.new(client_id: params[:client_id])
  end

  def create
    @project = Project.new(project_params)
    if @project.save
      redirect_to @project, notice: t("projects.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: t("projects.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to projects_path, notice: t("projects.delete_success")
  end

  # GET /projects/search?q=... (AJAX 자동완성용)
  def search
    q = params[:q].to_s.strip
    projects = Project.includes(:client).active.by_name
    projects = projects.where("projects.name LIKE ? OR projects.location LIKE ? OR projects.code LIKE ?", "%#{q}%", "%#{q}%", "%#{q}%") if q.present?
    projects = projects.where(client_id: params[:client_id]) if params[:client_id].present?
    results = projects.limit(10).map { |p| { id: p.id, name: p.name, client_name: p.client&.name, status: p.status } }
    render json: results
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(
      :client_id, :name, :code, :site_category, :location, :country,
      :budget, :currency, :start_date, :end_date, :status, :description, :active
    )
  end

  # ISS-382: 중복 require_manager! 제거 — ApplicationController 단일 정의 사용
end
