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
  end

  def show
    @orders = @project.orders.by_due_date.limit(20)
  end

  def new
    @project = Project.new(client_id: params[:client_id])
  end

  def create
    @project = Project.new(project_params)
    if @project.save
      redirect_to @project, notice: "프로젝트가 등록되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "프로젝트 정보가 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to projects_path, notice: "프로젝트가 삭제되었습니다."
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
