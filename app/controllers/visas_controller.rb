class VisasController < ApplicationController
  before_action :authenticate_user!
  before_action :set_employee
  before_action :set_visa, only: %i[edit update destroy]

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

  private

  def set_employee
    @employee = Employee.find(params[:employee_id])
  end

  def set_visa
    @visa = @employee.visas.find(params[:id])
  end

  def visa_params
    params.require(:visa).permit(:visa_type, :issuing_country, :visa_number,
                                 :issue_date, :expiry_date, :status, :notes)
  end
end
