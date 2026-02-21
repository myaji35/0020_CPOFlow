class EmploymentContractsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_employee
  before_action :set_contract, only: %i[edit update destroy]

  def new
    @contract = @employee.employment_contracts.new
    @projects = Project.by_name
  end

  def edit
    @projects = Project.by_name
  end

  def create
    @contract = @employee.employment_contracts.new(contract_params)
    if @contract.save
      redirect_to @employee, notice: "계약이 등록되었습니다."
    else
      @projects = Project.by_name
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @contract.update(contract_params)
      redirect_to @employee, notice: "계약이 수정되었습니다."
    else
      @projects = Project.by_name
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contract.destroy
    redirect_to @employee, notice: "계약이 삭제되었습니다."
  end

  private

  def set_employee
    @employee = Employee.find(params[:employee_id])
  end

  def set_contract
    @contract = @employee.employment_contracts.find(params[:id])
  end

  def contract_params
    params.require(:employment_contract).permit(
      :project_id, :start_date, :end_date, :base_salary, :currency,
      :pay_frequency, :status, :notes
    )
  end
end
