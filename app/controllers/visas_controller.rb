class VisasController < ApplicationController
  before_action :authenticate_user!
  # ISS-300: 비자 정보는 외국인 직원 거주권 관련 — manager 이상만 CRUD
  before_action :require_manager!
  before_action :set_employee
  before_action :set_visa, only: %i[edit update destroy start_renewal]

  def new
    @visa = @employee.visas.new
  end

  def edit; end

  def create
    @visa = @employee.visas.new(visa_params)
    if @visa.save
      redirect_to @employee, notice: t("visas.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @visa.update(visa_params)
      redirect_to @employee, notice: t("visas.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @visa.destroy
    redirect_to @employee, notice: t("visas.delete_success")
  end

  # ISS-205: 비자 갱신 워크플로우 시작
  # 갱신 시작 시각 + status 기록 → HR 프로세스 trigger 포인트 마킹
  def start_renewal
    if @visa.renewal_started_at.present?
      redirect_to @employee, alert: "이미 갱신 진행 중입니다 (시작: #{@visa.renewal_started_at.strftime('%Y-%m-%d')})"
      return
    end
    @visa.update!(
      renewal_started_at: Time.current,
      renewal_status: "in_progress",
      renewal_note: params[:note].to_s.strip
    )
    redirect_to @employee, notice: "비자 갱신 프로세스가 시작되었습니다. 담당자에게 통보하세요."
  end

  private

  def set_employee
    @employee = Employee.find(params[:employee_id])
  end

  def set_visa
    @visa = @employee.visas.find(params[:id])
  end

  def visa_params
    params.require(:visa).permit(:visa_type, :issuing_country, :visa_number,
                                 :issue_date, :expiry_date, :status, :notes,
                                 documents: [])
  end
end
