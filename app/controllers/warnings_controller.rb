# ISS-332: 경고장 CRUD
class WarningsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_member!, only: %i[new create edit update destroy acknowledge]
  before_action :set_employee
  before_action :set_warning, only: %i[show edit update destroy acknowledge]

  def index
    @warnings = @employee.warnings.recent
  end

  def show; end

  def new
    @warning = @employee.warnings.new(issued_at: Time.current, severity: "verbal", category: "other", status: "active")
  end

  def create
    @warning = @employee.warnings.new(warning_params)
    @warning.issued_by = current_user
    if @warning.save
      redirect_to employee_path(@employee, tab: "warnings"), notice: "경고장 발급됨"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @warning.update(warning_params)
      redirect_to employee_path(@employee, tab: "warnings"), notice: "경고장 수정됨"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @warning.destroy
    redirect_to employee_path(@employee, tab: "warnings"), notice: "경고장 삭제됨"
  end

  # 직원 본인이 확인 (acknowledged_at + signature)
  def acknowledge
    @warning.update(acknowledged_at: Time.current, status: "acknowledged",
                    acknowledged_signature: params[:signature].to_s.strip)
    redirect_to employee_path(@employee, tab: "warnings"), notice: "경고장이 확인 처리되었습니다."
  end

  private

  def set_employee
    @employee = Employee.find(params[:employee_id])
  end

  def set_warning
    @warning = @employee.warnings.find(params[:id])
  end

  def warning_params
    params.require(:warning).permit(:issued_at, :category, :severity, :subject, :description,
                                    :effective_until, :status, documents: [])
  end

  def require_member!
    redirect_to root_path, alert: "권한 없음" unless current_user&.member? || current_user&.manager? || current_user&.admin?
  end
end
