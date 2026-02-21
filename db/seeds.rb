# frozen_string_literal: true
# CPOFlow Seed Data — AtoZ2010 Inc.
# Run: bin/rails db:seed

puts "🌱 Seeding CPOFlow database..."

# ─── Users ───────────────────────────────────────────────────────────────────
admin = User.find_or_create_by!(email: "admin@atozone.com") do |u|
  u.name = "Admin User"; u.password = "password123"
  u.role = :admin; u.branch = :abu_dhabi; u.locale = "en"
end
manager_kss = User.find_or_create_by!(email: "kss@atozone.com") do |u|
  u.name = "Kim Seung-sik"; u.password = "password123"
  u.role = :manager; u.branch = :seoul; u.locale = "ko"
end
officer_ahmed = User.find_or_create_by!(email: "ahmed@atozone.com") do |u|
  u.name = "Ahmed Al-Rashid"; u.password = "password123"
  u.role = :member; u.branch = :abu_dhabi; u.locale = "ar"
end
officer_park = User.find_or_create_by!(email: "park@atozone.com") do |u|
  u.name = "Park Ji-young"; u.password = "password123"
  u.role = :member; u.branch = :seoul; u.locale = "ko"
end
officer_sarah = User.find_or_create_by!(email: "sarah@atozone.com") do |u|
  u.name = "Sarah Johnson"; u.password = "password123"
  u.role = :member; u.branch = :abu_dhabi; u.locale = "en"
end
puts "  ✓ #{User.count} users"

# ─── Suppliers ───────────────────────────────────────────────────────────────
Supplier.find_or_create_by!(code: "SIKA-001") do |s|
  s.name = "Sika AG"; s.country = "CH"
  s.contact_email = "procurement@sika.com"
  s.ecount_code = "SUP-SIKA"; s.active = true
  s.notes = "Primary supplier — Swiss construction chemicals. Waterproofing, concrete repair, adhesives, sealants."
end
Supplier.find_or_create_by!(code: "LOCAL-UAE-001") do |s|
  s.name = "Gulf Construction Materials LLC"; s.country = "AE"
  s.contact_email = "sales@gcmuae.com"; s.ecount_code = "SUP-GCM"; s.active = true
end
Supplier.find_or_create_by!(code: "KOR-001") do |s|
  s.name = "Korea Construction Supply Co."; s.country = "KR"
  s.contact_email = "export@kcs.co.kr"; s.ecount_code = "SUP-KCS"; s.active = true
end
puts "  ✓ #{Supplier.count} suppliers"

# ─── Clients (발주처) ─────────────────────────────────────────────────────────
enec = Client.find_or_create_by!(code: "CL-ENEC") do |c|
  c.name = "ENEC (Emirates Nuclear Energy Corp)"
  c.country = "AE"; c.industry = "nuclear"
  c.credit_grade = "A"; c.payment_terms = "NET30"; c.currency = "USD"
  c.ecount_code = "SP-006"
  c.notes = "UAE 원자력공사. 바라카 원전 4기 운영."
end
kepco = Client.find_or_create_by!(code: "CL-KEPCO") do |c|
  c.name = "KEPCO E&C (한국전력기술)"
  c.country = "KR"; c.industry = "nuclear"
  c.credit_grade = "A"; c.payment_terms = "NET60"; c.currency = "USD"
  c.ecount_code = "SP-007"
end
seoul_metro = Client.find_or_create_by!(code: "CL-SMTRO") do |c|
  c.name = "서울지하철 (Seoul Metro)"
  c.country = "KR"; c.industry = "gtx"
  c.credit_grade = "B"; c.payment_terms = "NET30"; c.currency = "KRW"
  c.ecount_code = "SP-008"
end
puts "  ✓ #{Client.count} clients"

# ─── Projects (프로젝트) ──────────────────────────────────────────────────────
barakah = Project.find_or_create_by!(code: "PRJ-BARK-3") do |p|
  p.client = enec; p.name = "바라카 원전 3호기 정비"
  p.site_category = "nuclear"; p.location = "Abu Dhabi, UAE"
  p.country = "AE"; p.budget = 800_000; p.currency = "USD"
  p.status = :active; p.start_date = 1.year.ago; p.end_date = 1.year.from_now
  p.description = "바라카 원전 3호기 연료봉 교체 주기 정비 조달"
end
gtx_a = Project.find_or_create_by!(code: "PRJ-GTX-A") do |p|
  p.client = seoul_metro; p.name = "GTX-A 노선 방수공사"
  p.site_category = "gtx"; p.location = "경기도 광명, 한국"
  p.country = "KR"; p.budget = 250_000; p.currency = "USD"
  p.status = :active; p.start_date = 6.months.ago; p.end_date = 6.months.from_now
end
shin_hanul = Project.find_or_create_by!(code: "PRJ-SH-34") do |p|
  p.client = kepco; p.name = "신한울 원전 3·4호기"
  p.site_category = "nuclear"; p.location = "경북 울진, 한국"
  p.country = "KR"; p.budget = 1_200_000; p.currency = "USD"
  p.status = :active; p.start_date = 2.years.ago; p.end_date = 3.years.from_now
end
puts "  ✓ #{Project.count} projects"

# ─── ContactPersons (담당자) ──────────────────────────────────────────────────
ContactPerson.find_or_create_by!(email: "ahmed.rashid@enec.gov.ae") do |cp|
  cp.contactable = enec; cp.name = "Ahmed Al-Rashid"
  cp.title = "Procurement Manager"; cp.phone = "+971-50-123-4567"
  cp.language = "ar"; cp.nationality = "UAE"; cp.primary = true
end
ContactPerson.find_or_create_by!(email: "kim.jh@kepco.co.kr") do |cp|
  cp.contactable = kepco; cp.name = "김정훈"
  cp.title = "구매팀장"; cp.phone = "+82-2-2105-8100"
  cp.language = "ko"; cp.nationality = "KR"; cp.primary = true
end
ContactPerson.find_or_create_by!(email: "lee.sy@seoulmetro.or.kr") do |cp|
  cp.contactable = seoul_metro; cp.name = "이수연"
  cp.title = "자재팀 대리"; cp.phone = "+82-2-6311-2001"
  cp.language = "ko"; cp.nationality = "KR"; cp.primary = true
end
puts "  ✓ #{ContactPerson.count} contact persons"

# ─── Products (Sika line) ─────────────────────────────────────────────────────
[
  { code: "SIKA-WP-001",  name: "Sika® Igolflex®-N",        category: "Waterproofing",       unit: "kg",        unit_price: 12.50, site_category: "tunnel"  },
  { code: "SIKA-WP-002",  name: "Sikaplan® WP 3100-15 TS",  category: "Waterproofing",       unit: "m2",        unit_price: 8.90,  site_category: "tunnel"  },
  { code: "SIKA-CR-001",  name: "Sika® MonoTop®-412 N",     category: "Concrete Repair",     unit: "kg",        unit_price: 5.20,  site_category: "nuclear" },
  { code: "SIKA-CR-002",  name: "SikaTop®-122 FA",          category: "Concrete Repair",     unit: "kg",        unit_price: 4.80,  site_category: "hydro"   },
  { code: "SIKA-ADH-001", name: "Sikadur®-31 CF Normal",    category: "Adhesives",           unit: "kg",        unit_price: 18.00, site_category: "general" },
  { code: "SIKA-INJ-001", name: "Sikaflex®-11 FC+",         category: "Sealants",            unit: "cartridge", unit_price: 9.50,  site_category: "gtx"     },
  { code: "SIKA-CON-001", name: "Sika® ViscoCrete®-5930",   category: "Concrete Admixtures", unit: "L",         unit_price: 3.20,  site_category: "hydro"   },
  { code: "SIKA-GRP-001", name: "SikaGrout®-314",           category: "Grouts",              unit: "kg",        unit_price: 2.10,  site_category: "nuclear" },
].each do |attrs|
  Product.find_or_create_by!(code: attrs[:code]) do |p|
    p.assign_attributes(attrs.merge(brand: "Sika", currency: "USD", active: true, sika_product: true, ecount_code: "EC-#{attrs[:code]}"))
  end
end
puts "  ✓ #{Product.count} products"

# ─── Sample Orders ────────────────────────────────────────────────────────────
[
  { title: "Sika Waterproofing - Barakah Nuclear Plant Phase 3",
    customer_name: "ENEC (Emirates Nuclear Energy Corp)",
    item_name: "Sika® MonoTop®-412 N", quantity: 5000, currency: "USD", estimated_value: 26000,
    status: :inbox, priority: :urgent, due_date: 7.days.from_now,
    tags: "nuclear,sika,UAE,waterproofing",
    description: "Emergency RFQ for concrete repair at Barakah NPP Unit 3 refueling shutdown.",
    original_email_from: "procurement@enec.gov.ae",
    original_email_subject: "RFQ: Concrete Repair Materials - Barakah Unit 3",
    user: admin },
  { title: "GTX-A Tunnel Sealant - 광명역 구간",
    customer_name: "현대건설 (Hyundai E&C)",
    item_name: "Sikaflex®-11 FC+", quantity: 3000, currency: "USD", estimated_value: 28500,
    status: :reviewing, priority: :high, due_date: 14.days.from_now,
    tags: "gtx,tunnel,korea,sika,sealant",
    description: "GTX-A Line tunnel joint sealant, Gwangmyeong Station section.",
    original_email_from: "materials@hdec.co.kr",
    original_email_subject: "견적요청: GTX-A 광명역 구간 실란트",
    user: manager_kss },
  { title: "Cheongpyeong Dam Waterproofing Repair",
    customer_name: "K-Water",
    item_name: "SikaTop®-122 FA", quantity: 8000, currency: "USD", estimated_value: 38400,
    status: :quoted, priority: :high, due_date: 21.days.from_now,
    tags: "hydro,dam,korea,sika",
    description: "Annual maintenance waterproofing for Cheongpyeong Dam spillway.",
    user: manager_kss },
  { title: "Abu Dhabi Metro Extension - Concrete Admixtures",
    customer_name: "Aldar Properties PJSC",
    item_name: "Sika® ViscoCrete®-5930", quantity: 12000, currency: "USD", estimated_value: 38400,
    status: :confirmed, priority: :medium, due_date: 30.days.from_now,
    tags: "uae,metro,tunnel,sika,admixtures",
    description: "Concrete admixture for Abu Dhabi Metro Phase 2 tunneling.",
    original_email_from: "procurement@aldar.com",
    user: officer_ahmed },
  { title: "Sika Grout - Shin-Hanul NPP Unit 3&4",
    customer_name: "KEPCO E&C",
    item_name: "SikaGrout®-314", quantity: 20000, currency: "USD", estimated_value: 42000,
    status: :procuring, priority: :urgent, due_date: 5.days.from_now,
    tags: "nuclear,korea,sika,grout",
    description: "Precision grout for equipment base plates at Shin-Hanul Nuclear Units 3&4.",
    user: manager_kss },
  { title: "Dubai Creek Tower - Structural Adhesive",
    customer_name: "Emaar Properties",
    item_name: "Sikadur®-31 CF Normal", quantity: 2500, currency: "USD", estimated_value: 45000,
    status: :qa, priority: :high, due_date: 3.days.from_now,
    tags: "uae,dubai,sika,adhesive,foundation",
    description: "Structural epoxy adhesive for post-installed rebar at tower foundation.",
    user: officer_sarah },
  { title: "Yeongwol PSP - Membrane Waterproofing",
    customer_name: "한국수력원자력 (KHNP)",
    item_name: "Sikaplan® WP 3100-15 TS", quantity: 15000, currency: "USD", estimated_value: 133500,
    status: :delivered, priority: :medium, due_date: 60.days.ago,
    tags: "hydro,korea,sika,waterproofing",
    description: "Completed: Membrane waterproofing for Yeongwol PSP underground cavern.",
    user: officer_park },
].each do |attrs|
  user = attrs.delete(:user)
  order = Order.find_or_create_by!(title: attrs[:title]) do |o|
    o.assign_attributes(attrs); o.user = user
  end
  Assignment.find_or_create_by!(order: order, user: user)
end
puts "  ✓ #{Order.count} orders"

# ─── Sample Tasks for reviewing order ────────────────────────────────────────
order = Order.find_by(status: "reviewing")
if order&.tasks&.empty?
  [
    { title: "Review RFQ specifications",       assignee: officer_ahmed, completed: true  },
    { title: "Check Sika product availability", assignee: officer_sarah, completed: true  },
    { title: "Request supplier quotation",      assignee: officer_ahmed, completed: false },
    { title: "Prepare commercial offer",        assignee: manager_kss,   completed: false },
    { title: "Submit quotation to client",      assignee: manager_kss,   completed: false },
  ].each { |t| order.tasks.create!(t.merge(due_date: 5.days.from_now)) }
end
puts "  ✓ #{Task.count} tasks"

# ─── Employees (직원) ─────────────────────────────────────────────────────────
emp_kim = Employee.find_or_create_by!(passport_number: "M12345678") do |e|
  e.name = "김민준"; e.name_en = "Kim Min-jun"
  e.nationality = "KR"; e.date_of_birth = Date.new(1985, 3, 15)
  e.phone = "+82-10-1234-5678"
  e.emergency_contact = "김철수 (부)"; e.emergency_phone = "+82-10-9876-5432"
  e.department = "구매팀"; e.job_title = "선임 구매 담당"
  e.employment_type = "regular"; e.hire_date = Date.new(2018, 1, 2)
  e.active = true
end
emp_arif = Employee.find_or_create_by!(passport_number: "PK98765432") do |e|
  e.name = "Muhammad Arif"; e.name_en = "Muhammad Arif"
  e.nationality = "PK"; e.date_of_birth = Date.new(1990, 7, 20)
  e.phone = "+971-55-234-5678"
  e.department = "현장지원"; e.job_title = "현장 조달 담당"
  e.employment_type = "dispatch"; e.hire_date = Date.new(2021, 6, 1)
  e.active = true
end
emp_ravi = Employee.find_or_create_by!(passport_number: "IN87654321") do |e|
  e.name = "Ravi Kumar"; e.name_en = "Ravi Kumar"
  e.nationality = "IN"; e.date_of_birth = Date.new(1988, 11, 5)
  e.phone = "+971-50-345-6789"
  e.department = "물류팀"; e.job_title = "물류 담당"
  e.employment_type = "contract"; e.hire_date = Date.new(2022, 3, 1)
  e.active = true
end
puts "  ✓ #{Employee.count} employees"

# ─── Visas ────────────────────────────────────────────────────────────────────
Visa.find_or_create_by!(employee: emp_kim, visa_type: "Employment", issuing_country: "AE") do |v|
  v.visa_number = "UAE-2024-KMJ-001"
  v.issue_date  = Date.new(2024, 1, 15)
  v.expiry_date = 45.days.from_now.to_date  # 만료 임박 테스트용
  v.status = "active"
  v.notes = "바라카 원전 현장 근무용 고용 비자"
end
Visa.find_or_create_by!(employee: emp_arif, visa_type: "Employment", issuing_country: "AE") do |v|
  v.visa_number = "UAE-2023-ARF-001"
  v.issue_date  = Date.new(2023, 6, 1)
  v.expiry_date = 2.years.from_now.to_date
  v.status = "active"
end
Visa.find_or_create_by!(employee: emp_ravi, visa_type: "Employment", issuing_country: "AE") do |v|
  v.visa_number = "UAE-2022-RVK-001"
  v.issue_date  = Date.new(2022, 3, 15)
  v.expiry_date = 20.days.from_now.to_date  # 위급 만료 테스트용
  v.status = "active"
end
puts "  ✓ #{Visa.count} visas"

# ─── Employment Contracts ─────────────────────────────────────────────────────
EmploymentContract.find_or_create_by!(employee: emp_kim) do |c|
  c.start_date  = Date.new(2024, 1, 1)
  c.end_date    = 25.days.from_now.to_date  # 계약 만료 임박 테스트용
  c.base_salary = 8_500; c.currency = "USD"; c.pay_frequency = "monthly"
  c.status = "active"; c.project = barakah
end
EmploymentContract.find_or_create_by!(employee: emp_arif) do |c|
  c.start_date  = Date.new(2023, 6, 1)
  c.end_date    = Date.new(2025, 5, 31)
  c.base_salary = 2_800; c.currency = "USD"; c.pay_frequency = "monthly"
  c.status = "active"; c.project = barakah
end
EmploymentContract.find_or_create_by!(employee: emp_ravi) do |c|
  c.start_date  = Date.new(2024, 3, 1)
  c.end_date    = Date.new(2025, 2, 28)
  c.base_salary = 2_200; c.currency = "USD"; c.pay_frequency = "monthly"
  c.status = "active"
end
puts "  ✓ #{EmploymentContract.count} contracts"

# ─── Employee Assignments (현장 배정) ─────────────────────────────────────────
EmployeeAssignment.find_or_create_by!(employee: emp_kim, project: barakah) do |a|
  a.role = "구매 담당자"; a.start_date = Date.new(2024, 1, 15)
  a.status = "active"
end
EmployeeAssignment.find_or_create_by!(employee: emp_arif, project: barakah) do |a|
  a.role = "현장 조달"; a.start_date = Date.new(2023, 6, 1)
  a.status = "active"
end
EmployeeAssignment.find_or_create_by!(employee: emp_ravi, project: shin_hanul) do |a|
  a.role = "물류 지원"; a.start_date = Date.new(2024, 3, 1)
  a.status = "active"
end
puts "  ✓ #{EmployeeAssignment.count} assignments"

# ─── Certifications ───────────────────────────────────────────────────────────
Certification.find_or_create_by!(employee: emp_kim, name: "산업안전산업기사") do |c|
  c.issuing_body = "한국산업인력공단"; c.issued_date = Date.new(2010, 5, 20)
end
Certification.find_or_create_by!(employee: emp_arif, name: "IOSH Safety Certificate") do |c|
  c.issuing_body = "IOSH"; c.issued_date = Date.new(2022, 8, 1)
  c.expiry_date  = Date.new(2025, 7, 31)
end
Certification.find_or_create_by!(employee: emp_ravi, name: "Forklift Operator License") do |c|
  c.issuing_body = "UAE MOHRE"; c.issued_date = Date.new(2023, 1, 10)
  c.expiry_date  = Date.new(2026, 1, 9)
end
puts "  ✓ #{Certification.count} certifications"

# ─── Org Chart: Countries ────────────────────────────────────────────────────
country_ae = Country.find_or_create_by!(code: "AE") do |c|
  c.name = "UAE"; c.name_en = "United Arab Emirates"
  c.region = "Middle East"; c.flag_emoji = "🇦🇪"; c.sort_order = 1
end
country_kr = Country.find_or_create_by!(code: "KR") do |c|
  c.name = "한국"; c.name_en = "South Korea"
  c.region = "Asia"; c.flag_emoji = "🇰🇷"; c.sort_order = 2
end
puts "  ✓ #{Country.count} countries"

# ─── Org Chart: Companies ─────────────────────────────────────────────────────
company_uae = Company.find_or_create_by!(name: "Gagahoho UAE LLC") do |c|
  c.country = country_ae; c.name_en = "Gagahoho UAE LLC"
  c.company_type = "site_office"; c.active = true
end
company_kr = Company.find_or_create_by!(name: "가가호호 주식회사") do |c|
  c.country = country_kr; c.name_en = "Gagahoho Inc."
  c.company_type = "hq"; c.active = true
end
puts "  ✓ #{Company.count} companies"

# ─── Org Chart: Departments ───────────────────────────────────────────────────
dept_eng  = Department.find_or_create_by!(company: company_uae, name: "Engineering") do |d|
  d.code = "ENG"; d.sort_order = 1
end
dept_proc = Department.find_or_create_by!(company: company_uae, name: "Procurement") do |d|
  d.code = "PRO"; d.sort_order = 2
end
dept_hr   = Department.find_or_create_by!(company: company_uae, name: "HR") do |d|
  d.code = "HR"; d.sort_order = 3
end
dept_mgmt = Department.find_or_create_by!(company: company_kr, name: "경영기획") do |d|
  d.code = "MGT"; d.sort_order = 1
end
puts "  ✓ #{Department.count} departments"

# ─── Employee → Department 배속 ───────────────────────────────────────────────
emp_kim.update(department: dept_hr)     if emp_kim.department_id.nil?
emp_arif.update(department: dept_eng)   if emp_arif.department_id.nil?
emp_ravi.update(department: dept_eng)   if emp_ravi.department_id.nil?
puts "  ✓ Employee department assignments updated"

# ─── Menu Permissions (기본값 설정) ──────────────────────────────────────────
MenuPermission::ROLES.each do |role|
  defaults = MenuPermission::DEFAULT_PERMISSIONS[role]
  MenuPermission::MENU_KEYS.each do |key|
    MenuPermission.find_or_create_by!(role: role, menu_key: key) do |p|
      p.can_read   = defaults[:can_read]
      p.can_create = defaults[:can_create]
      p.can_update = defaults[:can_update]
      p.can_delete = defaults[:can_delete]
    end
  end
end
puts "  ✓ #{MenuPermission.count} menu permissions"

puts ""
puts "✅ Seed complete!"
puts "   admin@atozone.com  / password123 (Admin)"
puts "   kss@atozone.com    / password123 (Manager, Seoul)"
puts "   ahmed@atozone.com  / password123 (Member, Abu Dhabi)"
