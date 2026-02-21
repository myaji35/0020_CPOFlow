class ContactPersonsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_contactable
  before_action :set_contact_person, only: %i[edit update destroy]

  def new
    @contact_person = @contactable.contact_persons.new
  end

  def create
    @contact_person = @contactable.contact_persons.new(contact_person_params)
    if @contact_person.save
      if primary_params?
        @contactable.contact_persons.where.not(id: @contact_person.id).update_all(primary: false)
      end
      redirect_to @contactable, notice: "담당자가 등록되었습니다."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @contact_person.update(contact_person_params)
      if @contact_person.primary?
        @contactable.contact_persons.where.not(id: @contact_person.id).update_all(primary: false)
      end
      redirect_to @contactable, notice: "담당자 정보가 수정되었습니다."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contact_person.destroy
    redirect_to @contactable, notice: "담당자가 삭제되었습니다."
  end

  private

  def set_contactable
    if params[:client_id]
      @contactable = Client.find(params[:client_id])
    elsif params[:supplier_id]
      @contactable = Supplier.find(params[:supplier_id])
    end
  end

  def set_contact_person
    @contact_person = @contactable.contact_persons.find(params[:id])
  end

  def contact_person_params
    params.require(:contact_person).permit(
      :name, :title, :email, :phone, :whatsapp, :wechat,
      :language, :nationality, :primary, :notes
    )
  end

  def primary_params?
    params.dig(:contact_person, :primary) == "1" || params.dig(:contact_person, :primary) == true
  end
end
