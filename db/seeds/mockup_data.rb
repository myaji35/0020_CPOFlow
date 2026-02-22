# frozen_string_literal: true
# CPOFlow 의사결정용 목업 데이터 (24개월 기간별 분석)
# Run: bin/rails runner db/seeds/mockup_data.rb

puts "📊 의사결정용 목업 데이터 생성 중..."

# ── 기존 레퍼런스 로드 ─────────────────────────────────────────────
admin      = User.find_by(email: "admin@atozone.com")
manager    = User.find_by(email: "kss@atozone.com")
ahmed      = User.find_by(email: "ahmed@atozone.com")
park       = User.find_by(email: "park@atozone.com")
sarah      = User.find_by(email: "sarah@atozone.com")

enec       = Client.find_by(code: "CL-ENEC")
kepco      = Client.find_by(code: "CL-KEPCO")
seoul_metro = Client.find_by(code: "CL-SMTRO")

sika       = Supplier.find_by(code: "SIKA-001")
gcm        = Supplier.find_by(code: "LOCAL-UAE-001")
kcs        = Supplier.find_by(code: "KOR-001")

barakah    = Project.find_by(code: "PRJ-BARK-3")
gtx_a      = Project.find_by(code: "PRJ-GTX-A")
shin_hanul = Project.find_by(code: "PRJ-SH-34")

# ── 추가 발주처 (Clients) ─────────────────────────────────────────
khnp = Client.find_or_create_by!(code: "CL-KHNP") do |c|
  c.name = "한국수력원자력 (KHNP)"; c.country = "KR"; c.industry = "nuclear"
  c.credit_grade = "A"; c.payment_terms = "NET60"; c.currency = "USD"
  c.ecount_code = "SP-009"; c.notes = "한국수력원자력. 국내 원전 운영."
end

kwater = Client.find_or_create_by!(code: "CL-KWATER") do |c|
  c.name = "K-Water (한국수자원공사)"; c.country = "KR"; c.industry = "hydro"
  c.credit_grade = "A"; c.payment_terms = "NET45"; c.currency = "KRW"
  c.ecount_code = "SP-010"
end

aldar = Client.find_or_create_by!(code: "CL-ALDAR") do |c|
  c.name = "Aldar Properties PJSC"; c.country = "AE"; c.industry = "gtx"
  c.credit_grade = "B"; c.payment_terms = "NET30"; c.currency = "USD"
  c.ecount_code = "SP-011"
end

hdec = Client.find_or_create_by!(code: "CL-HDEC") do |c|
  c.name = "현대건설 (Hyundai E&C)"; c.country = "KR"; c.industry = "tunnel"
  c.credit_grade = "A"; c.payment_terms = "NET30"; c.currency = "USD"
  c.ecount_code = "SP-012"
end

puts "  ✓ Clients: #{Client.count}개"

# ── 추가 프로젝트 ──────────────────────────────────────────────────
cheongpyeong = Project.find_or_create_by!(code: "PRJ-CPG-DAM") do |p|
  p.client = kwater; p.name = "청평댐 방수보수공사"
  p.site_category = "hydro"; p.location = "경기도 가평, 한국"
  p.country = "KR"; p.budget = 180_000; p.currency = "USD"
  p.status = :active; p.start_date = 8.months.ago; p.end_date = 4.months.from_now
end

ad_metro = Project.find_or_create_by!(code: "PRJ-ADM-P2") do |p|
  p.client = aldar; p.name = "Abu Dhabi Metro Phase 2"
  p.site_category = "tunnel"; p.location = "Abu Dhabi, UAE"
  p.country = "AE"; p.budget = 550_000; p.currency = "USD"
  p.status = :active; p.start_date = 10.months.ago; p.end_date = 14.months.from_now
end

yeongwol = Project.find_or_create_by!(code: "PRJ-YWL-PSP") do |p|
  p.client = khnp; p.name = "영월 양수발전소 지하공동 방수"
  p.site_category = "hydro"; p.location = "강원도 영월, 한국"
  p.country = "KR"; p.budget = 320_000; p.currency = "USD"
  p.status = :completed; p.start_date = 2.years.ago; p.end_date = 3.months.ago
end

gtx_b = Project.find_or_create_by!(code: "PRJ-GTX-B") do |p|
  p.client = hdec; p.name = "GTX-B 수원~서울 터널방수"
  p.site_category = "gtx"; p.location = "경기도 수원, 한국"
  p.country = "KR"; p.budget = 420_000; p.currency = "USD"
  p.status = :active; p.start_date = 3.months.ago; p.end_date = 18.months.from_now
end

puts "  ✓ Projects: #{Project.count}개"

# ── 24개월치 과거 발주 데이터 생성 ────────────────────────────────
users = [admin, manager, ahmed, park, sarah].compact
clients = [enec, kepco, seoul_metro, khnp, kwater, aldar, hdec].compact
projects = [barakah, gtx_a, shin_hanul, cheongpyeong, ad_metro, yeongwol, gtx_b].compact
suppliers_list = [sika, gcm, kcs].compact

# 월별 발주 패턴 (계절성 반영)
monthly_patterns = {
  1  => { count: 3,  base_value: 25_000 },  # 1월 — 연초 소강
  2  => { count: 4,  base_value: 28_000 },
  3  => { count: 6,  base_value: 35_000 },  # 3월 — 공사 시즌 시작
  4  => { count: 7,  base_value: 40_000 },
  5  => { count: 8,  base_value: 45_000 },
  6  => { count: 9,  base_value: 48_000 },  # 6월 — 성수기
  7  => { count: 7,  base_value: 42_000 },  # 7월 — 여름 더위
  8  => { count: 6,  base_value: 38_000 },
  9  => { count: 8,  base_value: 46_000 },  # 9월 — 가을 성수기
  10 => { count: 9,  base_value: 50_000 },
  11 => { count: 7,  base_value: 43_000 },
  12 => { count: 4,  base_value: 30_000 },  # 12월 — 연말 소강
}

order_templates = [
  { title_prefix: "원전 콘크리트 보수재", item: "Sika® MonoTop®-412 N",       category: "nuclear", value_mul: 1.2 },
  { title_prefix: "터널 실란트 조달",     item: "Sikaflex®-11 FC+",           category: "tunnel",  value_mul: 0.9 },
  { title_prefix: "댐 방수막 시공재",     item: "SikaTop®-122 FA",            category: "hydro",   value_mul: 1.1 },
  { title_prefix: "지하철 방수시트",      item: "Sikaplan® WP 3100-15 TS",    category: "gtx",     value_mul: 1.0 },
  { title_prefix: "구조용 에폭시 접착제", item: "Sikadur®-31 CF Normal",      category: "nuclear", value_mul: 1.5 },
  { title_prefix: "콘크리트 혼화제",      item: "Sika® ViscoCrete®-5930",     category: "tunnel",  value_mul: 0.7 },
  { title_prefix: "정밀 그라우트재",      item: "SikaGrout®-314",             category: "hydro",   value_mul: 0.8 },
  { title_prefix: "방수 멤브레인",        item: "Sika® Igolflex®-N",          category: "gtx",     value_mul: 1.3 },
]

created = 0

# 24개월 전부터 데이터 생성
24.downto(1) do |months_ago|
  month_date = Date.today - months_ago.months
  month = month_date.month
  pattern = monthly_patterns[month]

  pattern[:count].times do |i|
    template = order_templates[i % order_templates.length]
    client   = clients.sample
    project  = projects.select { |p| p.site_category == template[:category] }.sample || projects.sample
    supplier = suppliers_list.sample
    user     = users.sample

    # 날짜 분산 (월 내 랜덤)
    day = rand(1..28)
    created_date = month_date.beginning_of_month + day.days

    # 금액 (패턴 기반 + 랜덤 변동)
    value = (pattern[:base_value] * template[:value_mul] * (0.8 + rand * 0.4)).round(-2)

    # 상태 결정 (오래된 것일수록 delivered 비율 높음)
    status = if months_ago > 6
      rand < 0.85 ? :delivered : :quoted
    elsif months_ago > 3
      [:delivered, :delivered, :delivered, :qa, :procuring].sample
    else
      [:confirmed, :procuring, :qa, :reviewing, :inbox].sample
    end

    # 납기일 (생성일 + 14~60일)
    lead_days = rand(14..60)
    due = created_date + lead_days.days

    # 납기 준수 여부 (80% 준수)
    updated_at = if status == :delivered
      (rand < 0.80) ? (due - rand(0..5).days) : (due + rand(1..14).days)
    else
      created_date + rand(1..lead_days).days
    end

    title = "#{template[:title_prefix]} — #{client&.name&.split('(')&.first&.strip || '미지정'} #{month_date.strftime('%Y-%m')}-#{i+1}"

    Order.create!(
      title:           title,
      customer_name:   client&.name || "Unknown",
      client:          client,
      supplier:        supplier,
      project:         project,
      item_name:       template[:item],
      quantity:        rand(1000..20000),
      currency:        "USD",
      estimated_value: value,
      status:          status,
      priority:        [:low, :medium, :medium, :high, :urgent].sample,
      due_date:        due,
      tags:            "#{template[:category]},sika,mockup",
      user:            user,
      created_at:      created_date,
      updated_at:      updated_at
    )
    created += 1
  rescue => e
    # 중복 등 에러 무시
  end
end

puts "  ✓ 과거 발주 데이터: #{created}건 추가"
puts "  ✓ 총 발주 건수: #{Order.count}건"

# ── 추가 직원 데이터 ──────────────────────────────────────────────
additional_employees = [
  { name: "이지현", name_en: "Lee Ji-hyun", nationality: "KR",
    passport: "M98765432", dob: "1992-08-22", dept_name: "구매팀",
    title: "구매 담당", type: "regular", hire: "2020-03-02",
    phone: "+82-10-2345-6789", active: true },
  { name: "박성훈", name_en: "Park Sung-hun", nationality: "KR",
    passport: "M87654321", dob: "1988-12-10", dept_name: "물류팀",
    title: "물류 팀장", type: "regular", hire: "2017-07-01",
    phone: "+82-10-3456-7890", active: true },
  { name: "Fatima Al-Zaabi", name_en: "Fatima Al-Zaabi", nationality: "AE",
    passport: "AE12345678", dob: "1995-04-15", dept_name: "현장지원",
    title: "Site Coordinator", type: "regular", hire: "2022-09-01",
    phone: "+971-56-789-0123", active: true },
  { name: "Sanjay Patel", name_en: "Sanjay Patel", nationality: "IN",
    passport: "IN23456789", dob: "1986-06-30", dept_name: "물류팀",
    title: "Logistics Officer", type: "contract", hire: "2023-01-15",
    phone: "+971-55-678-9012", active: true },
  { name: "최영호", name_en: "Choi Young-ho", nationality: "KR",
    passport: "M76543210", dob: "1982-02-28", dept_name: "경영기획",
    title: "이사", type: "regular", hire: "2015-01-05",
    phone: "+82-10-4567-8901", active: true },
  { name: "Hassan Al-Muhairy", name_en: "Hassan Al-Muhairy", nationality: "AE",
    passport: "AE87654321", dob: "1991-11-03", dept_name: "현장지원",
    title: "Procurement Officer", type: "regular", hire: "2021-02-14",
    phone: "+971-50-456-7890", active: true },
  { name: "김태영", name_en: "Kim Tae-young", nationality: "KR",
    passport: "M65432109", dob: "1994-07-19", dept_name: "구매팀",
    title: "구매 담당 (계약직)", type: "contract", hire: "2024-01-02",
    phone: "+82-10-5678-9012", active: true },
  { name: "Diego Morales", name_en: "Diego Morales", nationality: "PH",
    passport: "PH34567890", dob: "1989-09-08", dept_name: "물류팀",
    title: "Warehouse Supervisor", type: "dispatch", hire: "2022-06-01",
    phone: "+971-55-567-8901", active: false, terminated: "2025-01-31" },
]

new_employees = []
additional_employees.each do |emp_data|
  emp = Employee.find_or_create_by!(passport_number: emp_data[:passport]) do |e|
    e.name = emp_data[:name]; e.name_en = emp_data[:name_en]
    e.nationality = emp_data[:nationality]
    e.date_of_birth = Date.parse(emp_data[:dob])
    e.phone = emp_data[:phone]
    # department 컬럼은 string 타입 (department_id가 별도 FK)
    e.write_attribute(:department, emp_data[:dept_name])
    e.job_title = emp_data[:title]
    e.employment_type = emp_data[:type]
    e.hire_date = Date.parse(emp_data[:hire])
    e.active = emp_data[:active]
    e.termination_date = emp_data[:terminated] ? Date.parse(emp_data[:terminated]) : nil
  end
  new_employees << emp
end

puts "  ✓ 총 직원 수: #{Employee.count}명"

# ── 추가 비자 데이터 ──────────────────────────────────────────────
visa_data = [
  { emp: new_employees[0], type: "Employment", country: "AE",
    num: "UAE-2024-LJH-001", issued: "2024-03-01", expiry: 90.days.from_now, status: "active" },
  { emp: new_employees[1], type: "Employment", country: "AE",
    num: "UAE-2022-PSH-001", issued: "2022-08-01", expiry: 15.days.from_now, status: "active" },  # 긴급!
  { emp: new_employees[2], type: "Employment", country: "AE",
    num: "UAE-2022-FAZ-001", issued: "2022-09-15", expiry: 3.years.from_now, status: "active" },
  { emp: new_employees[3], type: "Employment", country: "AE",
    num: "UAE-2023-SPT-001", issued: "2023-01-20", expiry: 35.days.from_now, status: "active" },  # 경고
  { emp: new_employees[4], type: "Residence",  country: "AE",
    num: "UAE-2024-CYH-001", issued: "2024-01-10", expiry: 2.years.from_now,  status: "active" },
  { emp: new_employees[5], type: "Employment", country: "AE",
    num: "UAE-2021-HAM-001", issued: "2021-03-01", expiry: 60.days.from_now,  status: "active" },  # 주의
  { emp: new_employees[6], type: "Employment", country: "AE",
    num: "UAE-2024-KTY-001", issued: "2024-01-15", expiry: 1.year.from_now,   status: "active" },
  { emp: new_employees[7], type: "Employment", country: "AE",
    num: "UAE-2022-DIM-001", issued: "2022-06-15", expiry: 5.days.ago,        status: "expired" }, # 만료됨
]

visa_data.each do |vd|
  next unless vd[:emp]
  Visa.find_or_create_by!(employee: vd[:emp], visa_type: vd[:type], issuing_country: vd[:country]) do |v|
    v.visa_number  = vd[:num]
    v.issue_date   = Date.parse(vd[:issued])
    v.expiry_date  = vd[:expiry].is_a?(Date) ? vd[:expiry] : vd[:expiry].to_date
    v.status       = vd[:status]
  end
end

puts "  ✓ 총 비자 수: #{Visa.count}건"

puts ""
puts "✅ 목업 데이터 생성 완료!"
puts "   발주 건수: #{Order.count}건 (24개월 기간별 분석 가능)"
puts "   프로젝트: #{Project.count}개 (nuclear/hydro/tunnel/gtx 전 카테고리)"
puts "   직원: #{Employee.count}명 / 비자: #{Visa.count}건"
puts "   → Google Sheets 동기화: bin/rails runner \"Sheets::SheetsService.new.sync_all\""
