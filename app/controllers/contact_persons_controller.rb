class ContactPersonsController < ApplicationController
  before_action :authenticate_user!
  # ISS-300: 외부 담당자 변경은 member 이상만 (viewer는 조회만)
  before_action :require_member!, only: %i[new create edit update destroy create_from_signature]
  # ISS-381: MenuPermission DB 2차 가드
  before_action -> { enforce_menu_permission!(:contact_persons, :create) }, only: %i[new create create_from_signature]
  before_action -> { enforce_menu_permission!(:contact_persons, :update) }, only: %i[edit update]
  before_action -> { enforce_menu_permission!(:contact_persons, :delete) }, only: %i[destroy]
  before_action :set_contactable, except: %i[index show create_from_signature search]
  before_action :set_contact_person, only: %i[edit update destroy]
  before_action :set_contact_person_standalone, only: %i[show]

  # GET /contact_persons — 전체 담당자 목록
  def index
    # KPI 카드 데이터
    all_cp = ContactPerson.all
    @kpi_total      = all_cp.count
    @kpi_clients    = all_cp.for_clients.count
    @kpi_suppliers  = all_cp.for_suppliers.count
    @kpi_recent_30d = all_cp.where("contact_persons.created_at >= ?", 30.days.ago).count

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
    @total_count  = @contact_persons.count
    @total_pages  = [ (@total_count / @per_page.to_f).ceil, 1 ].max
    @current_page = params[:page].to_i.clamp(1, @total_pages)
    @prev_page    = @current_page > 1 ? @current_page - 1 : nil
    @next_page    = @current_page < @total_pages ? @current_page + 1 : nil
    @contact_persons = @contact_persons.offset((@current_page - 1) * @per_page).limit(@per_page)
  end

  # GET /contact_persons/:id — 담당자 상세
  def show
    @contactable = @contact_person.contactable
    # 관련 Order: 발주처(Client) 또는 거래처(Supplier)를 통해 연결된 Order (최근 10건)
    if @contactable.is_a?(Client)
      @related_orders = Order.where(client: @contactable)
                             .order(created_at: :desc)
                             .limit(10)
    else
      @related_orders = Order.where(supplier: @contactable)
                             .order(created_at: :desc)
                             .limit(10)
    end

    # 이메일 이력: 담당자 이메일과 매칭되는 Order (이메일 수신 기록)
    if @contact_person.email.present?
      @email_orders = Order.where("original_email_from LIKE ?", "%#{@contact_person.email}%")
                           .order(created_at: :desc)
                           .limit(10)
    else
      @email_orders = Order.none
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

  def edit
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "new-contact-form-#{@contactable.id}",
          partial: "contact_persons/inline_form",
          locals: { contactable: @contactable, contact_person: @contact_person }
        )
      end
      format.html # 기존 edit.html.erb 페이지 (폴백)
    end
  end

  def update
    if @contact_person.update(contact_person_params)
      if @contact_person.primary?
        @contactable.contact_persons.where.not(id: @contact_person.id).update_all(primary: false)
      end

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            # 폼을 새 담당자 추가로 리셋
            turbo_stream.replace(
              "new-contact-form-#{@contactable.id}",
              partial: "contact_persons/inline_form",
              locals: { contactable: @contactable, contact_person: ContactPerson.new }
            ),
            # 수정된 행 업데이트
            turbo_stream.replace(
              "contact-person-#{@contact_person.id}",
              partial: "contact_persons/row",
              locals: { contact_person: @contact_person, contactable: @contactable }
            )
          ]
        end
        format.html { redirect_to @contactable, notice: t("contact_persons.update_success") }
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
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @contact_person.destroy

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.remove("contact-person-#{@contact_person.id}")
      end
      format.html do
        # 상세 페이지에서 삭제 시 목록으로, 탭에서 삭제 시 회사 상세로
        if request.referer&.include?("/contact_persons/")
          redirect_to contact_persons_path, notice: t("contact_persons.delete_success")
        else
          redirect_to @contactable, notice: t("contact_persons.delete_success")
        end
      end
    end
  end

  # GET /contact_persons/search?client_id=X&q=Y — 주문 폼 외부담당자 자동완성
  # 변경 이력 (UX 개선):
  #   - 표시 이름: 이메일 username(`Aaesha.s.alzaabi`) → 풀네임 형식(`Aaesha S Alzaabi`)
  #   - limit 20 → client_id 지정 시 100 (ENEC처럼 contact 多), 검색어 있으면 50
  #   - 정렬: primary 우선 + 풀네임(스페이스 포함) 우선, 그 다음 LOWER(name)
  def search
    q = params[:q].to_s.strip
    scope = ContactPerson.for_clients
    if params[:client_id].present?
      scope = scope.where(contactable_id: params[:client_id])
    end
    if q.present?
      term = "%#{q.downcase}%"
      scope = scope.where(
        "LOWER(contact_persons.name) LIKE :t OR LOWER(contact_persons.email) LIKE :t " \
        "OR contact_persons.phone LIKE :t OR contact_persons.mobile LIKE :t",
        t: term
      )
    end
    # 정렬: primary 우선 → 풀네임(공백 포함) 우선(자동import dot-name 후순위) → name ASC
    scope = scope.select("contact_persons.*, CASE WHEN name LIKE '% %' THEN 0 ELSE 1 END AS _name_priority")
                 .order(Arel.sql('"contact_persons"."primary" DESC, _name_priority ASC, LOWER(name) ASC'))
    limit = q.present? ? 50 : (params[:client_id].present? ? 100 : 30)
    results = scope.limit(limit).map do |cp|
      pretty = humanize_contact_name(cp.name)
      sub = [ cp.department, cp.email ].compact_blank.join(" · ")
      { id: cp.id, name: pretty, code: sub, primary: cp.primary, raw_name: cp.name }
    end
    render json: results
  end

  private

  # 자동 import된 이메일 username 형식(`aaesha.s.alzaabi` / `bernard.swanson`)을
  # 사람이 읽기 쉬운 풀네임으로 변환. 이미 공백 있는 이름은 그대로.
  def humanize_contact_name(raw)
    return raw if raw.blank?
    return raw if raw.include?(" ")  # 이미 풀네임 (Bosco Bobby 등)
    raw.split(".").map { |part| part.empty? ? part : part[0].upcase + part[1..].to_s.downcase }.join(" ")
  end
  public

  # POST /contact_persons/create_from_signature — Inbox 발신처 카드에서 담당자 저장
  def create_from_signature
    @order = Order.find_by(id: params[:order_id])

    unless @order
      respond_to do |format|
        format.json { render json: { success: false, error: "해당 오더를 찾을 수 없습니다. (ID: #{params[:order_id]})" }, status: :not_found }
        format.html { redirect_back fallback_location: inbox_path, alert: "해당 오더를 찾을 수 없습니다." }
      end
      return
    end

    sig = @order.email_signature_json.present? ? JSON.parse(@order.email_signature_json) : {}

    contactable = find_contactable_by_domain(@order.sender_domain)

    unless contactable
      msg = "발주처/거래처를 먼저 이 오더와 연결하세요. (도메인: #{@order.sender_domain.presence || '알 수 없음'})"
      respond_to do |format|
        format.json { render json: { success: false, error: msg }, status: :unprocessable_entity }
        format.html { redirect_back fallback_location: inbox_path, alert: msg }
      end
      return
    end

    # 발신자 이메일 추출
    sender_email = @order.original_email_from.to_s
                         .match(/<(.+?)>/)&.[](1) || @order.original_email_from.to_s.strip

    # 중복 체크
    existing = contactable.contact_persons.find_by(email: sender_email)
    if existing
      msg = "#{existing.name}님은 이미 #{contactable.name}의 담당자로 등록되어 있습니다."
      respond_to do |format|
        format.json { render json: { success: false, error: msg, existing_id: existing.id }, status: :conflict }
        format.html { redirect_back fallback_location: inbox_path, alert: msg }
      end
      return
    end

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
      respond_to do |format|
        format.json { render json: { success: true, contact_person: { id: @contact_person.id, name: @contact_person.name, email: @contact_person.email }, message: "#{@contact_person.name}님이 #{contactable.name}의 담당자로 저장되었습니다." } }
        format.html { redirect_back fallback_location: inbox_path, notice: "#{@contact_person.name}님이 #{contactable.name}의 담당자로 저장되었습니다." }
      end
    else
      errors = @contact_person.errors.full_messages
      msg = errors.any? ? "담당자 저장 실패: #{errors.join(', ')}" : "담당자 저장에 실패했습니다. 다시 시도해주세요."
      respond_to do |format|
        format.json { render json: { success: false, error: msg, details: errors }, status: :unprocessable_entity }
        format.html { redirect_back fallback_location: inbox_path, alert: msg }
      end
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
    Client.find_by("website LIKE ?", "%#{domain}%") ||
      Supplier.find_by("website LIKE ? OR contact_email LIKE ?", "%#{domain}%", "%#{domain}%")
  end
end
