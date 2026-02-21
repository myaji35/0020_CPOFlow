# frozen_string_literal: true

module Sheets
  # Google Sheets API v4 연동 서비스.
  # Service Account JSON이 credentials에 없으면 Mock 모드로 동작합니다.
  #
  # 실제 사용:
  #   bin/rails credentials:edit 에서 아래 설정 추가:
  #   google:
  #     sheets_spreadsheet_id: "1BxiM..."
  #     service_account:
  #       type: "service_account"
  #       project_id: "..."
  #       private_key: "-----BEGIN RSA PRIVATE KEY-----\n..."
  #       client_email: "cpoflow@project.iam.gserviceaccount.com"
  #       token_uri: "https://oauth2.googleapis.com/token"
  class SheetsService
    SCOPE = "https://www.googleapis.com/auth/spreadsheets"

    def initialize
      @mock_mode = service_account_config.blank? || spreadsheet_id.blank?
      @service   = build_client unless @mock_mode
    end

    def mock_mode? = @mock_mode

    # 전체 동기화 실행. 성공 시 SheetsSyncLog 반환.
    def sync_all
      log = SheetsSyncLog.create!(
        status: "pending",
        spreadsheet_id: spreadsheet_id.presence || "mock-spreadsheet"
      )

      if @mock_mode
        run_mock(log)
      else
        run_real(log)
      end

      log
    end

    private

    # ── Mock 모드 ──────────────────────────────────────────────
    def run_mock(log)
      orders_cnt    = Order.count
      projects_cnt  = Project.count
      employees_cnt = Employee.active.count
      visas_cnt     = Visa.where(status: "active").count

      # Mock: 실제 API 호출 없이 카운트만 기록
      Rails.logger.info "[SheetsService] Mock mode — skipping API call"
      Rails.logger.info "[SheetsService] Would sync: orders=#{orders_cnt}, projects=#{projects_cnt}, employees=#{employees_cnt}, visas=#{visas_cnt}"

      log.update!(
        status:          "mock",
        orders_count:    orders_cnt,
        projects_count:  projects_cnt,
        employees_count: employees_cnt,
        visas_count:     visas_cnt,
        synced_at:       Time.current
      )
    end

    # ── 실제 API 모드 ──────────────────────────────────────────
    def run_real(log)
      sync_orders(log)
      sync_projects(log)
      sync_employees(log)
      sync_visas(log)

      log.update!(status: "success", synced_at: Time.current)
    rescue Google::Apis::AuthorizationError => e
      log.update!(status: "failed", error_message: "인증 오류: #{e.message}")
      Rails.logger.error "[SheetsService] AuthorizationError: #{e.message}"
      raise
    rescue Google::Apis::Error => e
      log.update!(status: "failed", error_message: "API 오류: #{e.message}")
      Rails.logger.error "[SheetsService] API Error: #{e.message}"
      raise
    rescue => e
      log.update!(status: "failed", error_message: e.message)
      Rails.logger.error "[SheetsService] Error: #{e.message}"
      raise
    end

    # ── API 클라이언트 빌드 ────────────────────────────────────
    def build_client
      credentials = Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(service_account_config.to_json),
        scope:       SCOPE
      )
      svc = Google::Apis::SheetsV4::SheetsService.new
      svc.authorization = credentials
      svc
    end

    def service_account_config
      @service_account_config ||= Rails.application.credentials.dig(:google, :service_account)
    end

    def spreadsheet_id
      @spreadsheet_id ||= Rails.application.credentials.dig(:google, :sheets_spreadsheet_id)
    end

    # ── 시트별 Push 메서드 ────────────────────────────────────
    def update_sheet(sheet_name, headers, rows)
      values = [ headers ] + rows
      range  = "#{sheet_name}!A1"
      body   = Google::Apis::SheetsV4::ValueRange.new(values: values)

      @service.update_spreadsheet_value(
        spreadsheet_id,
        range,
        body,
        value_input_option: "USER_ENTERED"
      )

      Rails.logger.info "[SheetsService] Updated '#{sheet_name}': #{rows.size} rows"
    end

    def sync_orders(log)
      headers = %w[ID 제목 고객사 공급사 상태 우선순위 납기일 품목 수량 견적가 통화 생성일]
      rows = Order.includes(:client, :supplier)
                  .order(created_at: :desc)
                  .limit(500)
                  .map do |o|
        [ o.id, o.title, o.client&.name, o.supplier&.name,
          o.status, o.priority,
          o.due_date&.strftime("%Y-%m-%d"),
          o.item_name, o.quantity,
          o.estimated_value, o.currency,
          o.created_at.strftime("%Y-%m-%d") ]
      end
      update_sheet("발주현황", headers, rows)
      log.update_column(:orders_count, rows.size)
    end

    def sync_projects(log)
      headers = %w[ID 현장명 코드 발주처 국가 상태 예산 통화 시작일 종료일]
      rows = Project.includes(:client)
                    .order(created_at: :desc)
                    .map do |p|
        [ p.id, p.name, p.code, p.client&.name, p.country,
          p.status, p.budget, p.currency,
          p.start_date&.strftime("%Y-%m-%d"),
          p.end_date&.strftime("%Y-%m-%d") ]
      end
      update_sheet("현장현황", headers, rows)
      log.update_column(:projects_count, rows.size)
    end

    def sync_employees(log)
      headers = %w[ID 이름 국적 직책 부서 고용형태 입사일 상태]
      rows = Employee.includes(:department)
                     .order(:name)
                     .map do |e|
        [ e.id, e.name, e.nationality, e.job_title,
          e.department&.name || e.department,
          e.employment_type,
          e.hire_date&.strftime("%Y-%m-%d"),
          e.active? ? "재직" : "퇴직" ]
      end
      update_sheet("직원현황", headers, rows)
      log.update_column(:employees_count, rows.size)
    end

    def sync_visas(log)
      headers = %w[직원명 비자유형 발급국 비자번호 만료일 D-Day 상태]
      rows = Visa.includes(:employee)
                 .where(status: "active")
                 .order(:expiry_date)
                 .map do |v|
        days = v.expiry_date ? (v.expiry_date - Date.today).to_i : "N/A"
        [ v.employee&.name, v.visa_type, v.issuing_country,
          v.visa_number,
          v.expiry_date&.strftime("%Y-%m-%d"),
          days, v.status ]
      end
      update_sheet("비자만료현황", headers, rows)
      log.update_column(:visas_count, rows.size)
    end
  end
end
