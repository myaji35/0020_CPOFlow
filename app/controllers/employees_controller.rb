require "csv"

class EmployeesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_employee, only: %i[show edit update destroy]
  # ISS-264: viewer read-only — CRUD는 member 이상만
  before_action :require_member!, only: %i[new create edit update]
  before_action :require_manager!, only: %i[destroy]

  def index
    @employees = Employee.includes(:visas, :employment_contracts, :employee_assignments, :department).by_name
    @employees = @employees.where(active: true) unless params[:show_inactive] == "1"
    if params[:q].present?
      @employees = @employees.where("name LIKE ? OR name_en LIKE ?",
                                   "%#{params[:q]}%", "%#{params[:q]}%")
    end
    @employees = @employees.where(department_id: params[:department]) if params[:department].present?
    @employees = @employees.where(employment_type: params[:type]) if params[:type].present?
    @employees = @employees.where(job_title: params[:job_title]) if params[:job_title].present?
    @employees = @employees.dispatched if params[:deployed] == "1"
    # AUDIT-005: 미매핑 필터
    @employees = @employees.unmapped if params[:filter] == "unmapped"
    if params[:expiring] == "visa"
      @employees = @employees.joins(:visas).merge(Visa.expiring_within(60)).distinct
    elsif params[:expiring] == "contract"
      @employees = @employees.joins(:employment_contracts).merge(EmploymentContract.expiring_within(30)).distinct
    end

    @stats = {
      total:             Employee.active.count,
      dispatched:        Employee.active.dispatched.count,
      unmapped:          Employee.active.unmapped.count,  # AUDIT-005
      visa_expiring:     Employee.active.joins(:visas).merge(Visa.expiring_within(60)).distinct.count,
      # ISS-205: 갱신 미시작 카운트
      visa_renewal_needed: Employee.active.joins(:visas)
                                   .merge(Visa.expiring_within(60).where(renewal_started_at: nil))
                                   .distinct.count,
      visa_in_renewal:   Employee.active.joins(:visas)
                                 .where(visas: { renewal_status: "in_progress" })
                                 .distinct.count,
      contract_expiring: Employee.active.joins(:employment_contracts)
                                 .merge(EmploymentContract.expiring_within(30)).distinct.count
    }
    @departments = Department.active.by_sort
    @job_titles  = JobTitle.active.by_sort

    # ISS-311: CSV export — 페이지네이션 전에 전체 relation 보관
    full_employees = @employees

    respond_to do |format|
      format.html do
        # ISS-310: 페이지네이션 — 직원 100명+ 시 전체 로드 방지
        @pagy, @employees = pagy(@employees, items: 25)
      end
      format.csv do
        # ISS-311: admin/manager만 export 허용
        return head :forbidden unless current_user.admin_or_manager?

        csv_data = export_employees_csv(full_employees)
        send_data "\xEF\xBB\xBF" + csv_data,
                  type: "text/csv; charset=utf-8",
                  disposition: "attachment",
                  filename: "employees-#{Date.today}.csv"
      end
    end
  end

  def show
    @visas          = @employee.visas.by_expiry
    @contracts      = @employee.employment_contracts.by_start
    @certifications = @employee.certifications.by_expiry
    # ISS-332: 경고장 (현장배정/휴가 탭 제거)
    @warnings       = @employee.warnings.recent
    @warnings_count = @warnings.size
  end

  def new
    @employee = Employee.new
  end

  def create
    @employee = Employee.new(employee_params)
    if @employee.save
      redirect_to @employee, notice: t("employees.create_success")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @employee.update(employee_params)
      respond_to do |format|
        format.html { redirect_to @employee, notice: t("employees.update_success") }
        format.json { render json: { ok: true, id: @employee.id, department_id: @employee.department_id } }
      end
    else
      respond_to do |format|
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: { ok: false, errors: @employee.errors.full_messages }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @employee.destroy
    redirect_to employees_path, notice: t("employees.delete_success")
  end

  private

  def set_employee
    @employee = Employee.find(params[:id])
  end

  def employee_params
    params.require(:employee).permit(
      :user_id, :email, :name, :name_en, :nationality, :passport_number, :date_of_birth,
      :phone, :emergency_contact, :emergency_phone, :department_id, :job_title,
      :employment_type, :hire_date, :termination_date, :active, :notes,
      documents: []
    )
  end

  # ISS-311: CSV export
  def export_employees_csv(employees)
    CSV.generate(headers: true) do |csv|
      csv << [ "#", "이름(한글)", "이름(영문)", "국적", "여권번호", "전화", "이메일",
              "부서", "직급", "고용형태", "입사일", "퇴직일", "재직중" ]
      employees.find_each do |e|
        csv << [
          e.id, e.name, e.name_en, e.nationality, e.passport_number,
          e.phone, e.email, e.department&.name, e.job_title,
          e.employment_type, e.hire_date, e.termination_date, e.active ? "Y" : "N"
        ]
      end
    end
  end
end
