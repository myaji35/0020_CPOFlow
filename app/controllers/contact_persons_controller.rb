class ContactPersonsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_contactable, except: %i[index show create_from_signature]
  before_action :set_contact_person, only: %i[edit update destroy]
  before_action :set_contact_person_standalone, only: %i[show]

  # GET /contact_persons — 전체 담당자 목록
  def index
    rel = ContactPerson.with_contactable
                       .search(params[:q])
                       .by_department(params[:department])

    rel = case params[:type]
    when "clients"   then rel.for_clients
    when "suppliers" then rel.for_suppliers
    else rel
    end

    @contact_persons = case params[:sort]
    when "recent"  then rel.recently_contacted
    when "company" then rel.order("contactable_type ASC, contact_persons.name ASC")
    else rel.primary_first
    end

    @per_page     = 24
    @current_page = [params[:page].to_i, 1].max
    @total_count  = @contact_persons.count
    @total_pages  = (@total_count / @per_page.to_f).ceil
    @total_pages  = 1 if @total_pages < 1
    @prev_page    = @current_page > 1 ? @current_page - 1 : nil
    @next_page    = @current_page < @total_pages ? @current_page + 1 : nil
    @contact_persons = @contact_persons.offset((@current_page - 1) * @per_page).limit(@per_page)
  end

  # GET /contact_persons/:id — 담당자 상세
  def show
    @contactable = @contact_person.contactable
    # 관련 Order: 발주처(Client) 또는 거래처(Supplier)를 통해 연결된 Order
    if @contactable.is_a?(Client)
      @related_orders = Order.where(client: @contactable)
                             .order(created_at: :desc)
                             .limit(20)
    else
      @related_orders = Order.where(supplier: @contactable)
                             .order(created_at: :desc)
                             .limit(20)
    end
  end

  def new
    @contact_person = @contactable.contact_persons.new
  end

  def create
    @contact_person = @contactable.contact_persons.new(contact_person_params)
    @contact_person.source ||= "manual"

    if @contact_person.save
      if primary_params?
        @contactable.contact_persons.where.not(id: @contact_person.id).update_all(primary: false)
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.append(
              "contact-persons-#{@contactable.id}",
              partial: "contact_persons/row",
              locals: { contact_person: @contact_person, contactable: @contactable }
            ),
            turbo_stream.replace(
              "new-contact-form-#{@contactable.id}",
              partial: "contact_persons/inline_form",
              locals: { contactable: @contactable, contact_person: ContactPerson.new }
            )
          ]
        end
        format.html { redirect_to @contactable, notice: t("contact_persons.create_success") }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "new-contact-form-#{@contactable.id}",
            partial: "contact_persons/inline_form",
            locals: { contactable: @contactable, contact_person: @contact_person }
          )
        end
        format.html { render :new, status: :unprocessable_entity }
      end
    end
  end

  def edit; end

  def update
    if @contact_person.update(contact_person_params)
      if @contact_person.primary?
        @contactable.contact_persons.where.not(id: @contact_person.id).update_all(primary: false)
      end
      redirect_to @contactable, notice: t("contact_persons.update_success")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contact_person.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("contact-person-#{@contact_person.id}")
      end
      format.html { redirect_to @contactable, notice: t("contact_persons.delete_success") }
    end
  end

  # POST /contact_persons/create_from_signature — Inbox 발신처 카드에서 담당자 저장
  def create_from_signature
    @order = Order.find(params[:order_id])
    sig    = @order.email_signature_json.present? ? JSON.parse(@order.email_signature_json) : {}

    contactable = find_contactable_by_domain(@order.sender_domain)

    unless contactable
      redirect_back fallback_location: inbox_path,
                    alert: "발주처/거래처를 먼저 이 오더와 연결하세요."
      return
    end

    # 발신자 이메일 추출
    sender_email = @order.original_email_from.to_s
                         .match(/<(.+?)>/)&.[](1) || @order.original_email_from.to_s.strip

    @contact_person = contactable.contact_persons.new(
      name:      sig["name"].presence || sender_email.split("@").first.humanize,
      title:     sig["title"],
      email:     sig["email"].presence || sender_email,
      phone:     sig["phone"],
      mobile:    sig["mobile"],
      source:    "email_signature"
    )

    if @contact_person.save
      @contact_person.update_column(:last_contacted_at, @order.created_at)
      redirect_back fallback_location: inbox_path,
                    notice: "#{@contact_person.name}님이 #{contactable.name}의 담당자로 저장되었습니다."
    else
      redirect_back fallback_location: inbox_path,
                    alert: @contact_person.errors.full_messages.join(", ")
    end
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

  def set_contact_person_standalone
    @contact_person = ContactPerson.find(params[:id])
  end

  def contact_person_params
    params.require(:contact_person).permit(
      :name, :title, :email, :phone, :mobile, :whatsapp, :wechat,
      :linkedin, :department, :language, :nationality, :primary, :notes
    )
  end

  def primary_params?
    params.dig(:contact_person, :primary) == "1" || params.dig(:contact_person, :primary) == true
  end

  # sender_domain으로 Client 또는 Supplier 검색
  def find_contactable_by_domain(domain)
    return nil if domain.blank?
    Client.find_by("website LIKE ? OR email LIKE ?", "%#{domain}%", "%#{domain}%") ||
      Supplier.find_by("website LIKE ? OR email LIKE ?", "%#{domain}%", "%#{domain}%")
  end
end
