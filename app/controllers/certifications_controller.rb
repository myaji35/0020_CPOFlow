class CertificationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_employee
  before_action :set_certification, only: %i[edit update destroy]

  def new
    @certification = @employee.certifications.new
  end

  def edit; end

  def create
    @certification = @employee.certifications.new(certification_params)
    if @certification.save
      redirect_to @employee, notice: "자격증이 등록되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @certification.update(certification_params)
      redirect_to @employee, notice: "자격증이 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @certification.destroy
    redirect_to @employee, notice: "자격증이 삭제되었습니다."
  end

  private

  def set_employee
    @employee = Employee.find(params[:employee_id])
  end

  def set_certification
    @certification = @employee.certifications.find(params[:id])
  end

  def certification_params
    params.require(:certification).permit(:name, :issuing_body, :issued_date, :expiry_date, :notes)
  end
end
