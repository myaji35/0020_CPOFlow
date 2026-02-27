class ProjectsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_project, only: %i[show edit update destroy]
  before_action :require_manager!, only: %i[destroy]

  def index
    @projects = Project.includes(:client, :orders).by_name
    @projects = @projects.where(site_category: params[:category]) if params[:category].present?
    @projects = @projects.where(status: params[:status]) if params[:status].present?
    @projects = @projects.where(client_id: params[:client_id]) if params[:client_id].present?
    @projects = @projects.where("projects.name LIKE ?", "%#{params[:q]}%") if params[:q].present?

    # FR-07: 통계 카드
    all_projects     = Project.includes(:orders).all
    @total_budget    = all_projects.sum { |p| p.budget.to_f }
    @total_utilized  = all_projects.sum(&:budget_utilized)
    @active_count    = Project.active.count
  end

  def show
    # FR-04: 관련 오더 탭 강화
    orders_scope = @project.orders
    case params[:period]
    when "this_month" then orders_scope = orders_scope.where(created_at: Time.current.beginning_of_month..)
    when "3months"    then orders_scope = orders_scope.where(created_at: 3.months.ago..)
    when "this_year"  then orders_scope = orders_scope.where(created_at: Time.current.beginning_of_year..)
    end

    @orders              = orders_scope.by_due_date.includes(:client, :supplier, :assignees)
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
    projects = projects.where("projects.name LIKE ?", "%#{q}%") if q.present?
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

  def require_manager!
    unless current_user.manager? || current_user.admin?
      redirect_to projects_path, alert: "권한이 없습니다."
    end
  end
end
