class EmployeeAssignmentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_employee
  before_action :set_assignment, only: %i[edit update destroy]

  def new
    @assignment = @employee.employee_assignments.new
    @projects   = Project.active.by_name
  end

  def edit
    @projects = Project.by_name
  end

  def create
    @assignment = @employee.employee_assignments.new(assignment_params)
    if @assignment.save
      redirect_to @employee, notice: "현장 배정이 등록되었습니다."
    else
      @projects = Project.active.by_name
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @assignment.update(assignment_params)
      redirect_to @employee, notice: "현장 배정이 수정되었습니다."
    else
      @projects = Project.by_name
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @assignment.destroy
    redirect_to @employee, notice: "현장 배정이 삭제되었습니다."
  end

  private

  def set_employee
    @employee = Employee.find(params[:employee_id])
  end

  def set_assignment
    @assignment = @employee.employee_assignments.find(params[:id])
  end

  def assignment_params
    params.require(:employee_assignment).permit(:project_id, :role, :start_date, :end_date, :status, :notes)
  end
end
