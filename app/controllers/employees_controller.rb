class EmployeesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_employee, only: %i[show edit update destroy]
  before_action :require_manager!, only: %i[destroy]

  def index
    @employees = Employee.includes(:visas, :employment_contracts, :employee_assignments).by_name
    @employees = @employees.where(active: true) unless params[:show_inactive] == "1"
    if params[:q].present?
      @employees = @employees.where("name LIKE ? OR name_en LIKE ?",
                                   "%#{params[:q]}%", "%#{params[:q]}%")
    end
    @employees = @employees.where(department: params[:department]) if params[:department].present?
    @employees = @employees.where(employment_type: params[:type]) if params[:type].present?
    @employees = @employees.dispatched if params[:deployed] == "1"

    @stats = {
      total:             Employee.active.count,
      dispatched:        Employee.active.dispatched.count,
      visa_expiring:     Employee.active.joins(:visas).merge(Visa.expiring_within(60)).distinct.count,
      contract_expiring: Employee.active.joins(:employment_contracts)
                                 .merge(EmploymentContract.expiring_within(30)).distinct.count
    }
  end

  def show
    @visas          = @employee.visas.by_expiry
    @contracts      = @employee.employment_contracts.by_start
    @assignments    = @employee.employee_assignments.includes(:project).by_start
    @certifications = @employee.certifications.by_expiry
  end

  def new
    @employee = Employee.new
  end

  def create
    @employee = Employee.new(employee_params)
    if @employee.save
      redirect_to @employee, notice: "직원이 등록되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @employee.update(employee_params)
      redirect_to @employee, notice: "직원 정보가 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @employee.destroy
    redirect_to employees_path, notice: "직원이 삭제되었습니다."
  end

  private

  def set_employee
    @employee = Employee.find(params[:id])
  end

  def employee_params
    params.require(:employee).permit(
      :user_id, :name, :name_en, :nationality, :passport_number, :date_of_birth,
      :phone, :emergency_contact, :emergency_phone, :department, :job_title,
      :employment_type, :hire_date, :termination_date, :active, :notes
    )
  end

end
