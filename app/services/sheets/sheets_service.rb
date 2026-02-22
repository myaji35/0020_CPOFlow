# frozen_string_literal: true

module Sheets
  # Google Sheets API v4 연동 서비스.
  #
  # 시트 구성:
  #   [대시보드]  — 차트 전용 탭 (EmbeddedChart + Slicer 기간 필터)
  #   [월별데이터] — 24개월 원본 데이터 (차트 데이터소스)
  #   [분기데이터] — 8분기 원본 데이터 (차트 데이터소스)
  #   [현장별실적] — 카테고리별 집계
  #   [발주현황]  — 전체 발주 원데이터 500건
  #   [HR현황]    — 직원 + 비자 만료
  #
  # Service Account 없을 때: Mock 모드
  class SheetsService
    SCOPE = "https://www.googleapis.com/auth/spreadsheets"
    SITE_CATEGORIES = %w[nuclear hydro tunnel gtx].freeze

    def initialize
      @mock_mode = service_account_config.blank? || spreadsheet_id.blank?
      @service   = build_client unless @mock_mode
    end

    def mock_mode? = @mock_mode

    def sync_all
      log = SheetsSyncLog.create!(
        status: "pending",
        spreadsheet_id: spreadsheet_id.presence || "mock-spreadsheet"
      )
      @mock_mode ? run_mock(log) : run_real(log)
      log
    end

    private

    # ── Mock 모드 ──────────────────────────────────────────────
    def run_mock(log)
      Rails.logger.info "[SheetsService] Mock mode"
      log.update!(
        status:          "mock",
        orders_count:    Order.count,
        projects_count:  Project.count,
        employees_count: Employee.active.count,
        visas_count:     Visa.where(status: "active").count,
        synced_at:       Time.current
      )
    end

    # ── 실제 API 모드 ──────────────────────────────────────────
    def run_real(log)
      # 1단계: 데이터 시트 업데이트
      sync_monthly_data(log)
      sync_quarterly_data(log)
      sync_site_category(log)
      sync_orders_raw(log)
      sync_hr_status(log)

      # 2단계: 대시보드 탭 (차트 + 슬라이서) 재구성
      build_dashboard_tab

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
      @spreadsheet_id ||= AppConfig.sheets_spreadsheet_id
    end

    def existing_sheet_titles
      @existing_sheet_titles ||= begin
        spreadsheet = @service.get_spreadsheet(spreadsheet_id)
        spreadsheet.sheets.map { |s| s.properties.title }
      end
    end

    def sheet_id_for(title)
      @sheet_id_cache ||= begin
        spreadsheet = @service.get_spreadsheet(spreadsheet_id)
        spreadsheet.sheets.each_with_object({}) do |s, h|
          h[s.properties.title] = s.properties.sheet_id
        end
      end
      @sheet_id_cache[title]
    end

    def ensure_sheet_exists(sheet_name)
      return if existing_sheet_titles.include?(sheet_name)

      request = Google::Apis::SheetsV4::AddSheetRequest.new(
        properties: Google::Apis::SheetsV4::SheetProperties.new(title: sheet_name)
      )
      batch = Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(
        requests: [ Google::Apis::SheetsV4::Request.new(add_sheet: request) ]
      )
      @service.batch_update_spreadsheet(spreadsheet_id, batch)
      @existing_sheet_titles << sheet_name
      @sheet_id_cache = nil  # 캐시 무효화
      Rails.logger.info "[SheetsService] Created sheet '#{sheet_name}'"
    end

    def update_sheet(sheet_name, headers, rows)
      ensure_sheet_exists(sheet_name)
      values = [ headers ] + rows
      range  = "#{sheet_name}!A1"
      body   = Google::Apis::SheetsV4::ValueRange.new(values: values)
      @service.update_spreadsheet_value(
        spreadsheet_id, range, body,
        value_input_option: "USER_ENTERED"
      )
      Rails.logger.info "[SheetsService] Updated '#{sheet_name}': #{rows.size} rows"
    end

    # ══════════════════════════════════════════════════════════
    # 데이터 시트들
    # ══════════════════════════════════════════════════════════

    # ── 월별 원본 데이터 (24개월) ─────────────────────────────
    def sync_monthly_data(log)
      headers = %w[년월 수주건수 납품건수 진행중 납기준수율 수주금액USD 평균납기일수]
      months  = (0..23).map { |i| (Date.today - i.months).beginning_of_month }.reverse

      rows = months.map do |month|
        ps = month.beginning_of_month
        pe = month.end_of_month

        mo   = Order.where(created_at: ps..pe)
        del  = mo.where(status: "delivered")
        ot   = del.where("due_date >= date(updated_at)")
        rate = del.count > 0 ? (ot.count.to_f / del.count * 100).round(1) : 0
        avg  = del.where.not(due_date: nil)
                  .average("CAST((julianday(due_date) - julianday(date(created_at))) AS FLOAT)")
        [
          month.strftime("%Y-%m"),
          mo.count, del.count,
          mo.where.not(status: "delivered").count,
          rate,
          mo.sum(:estimated_value).to_f.round(0),
          avg&.round(1) || 0
        ]
      end

      update_sheet("월별데이터", headers, rows)
      log.update_column(:orders_count, rows.sum { |r| r[1].to_i })
    end

    # ── 분기 원본 데이터 ──────────────────────────────────────
    def sync_quarterly_data(log)
      headers = %w[년도 분기 수주건수 납품건수 납기준수율 총수주금액USD 최대단건금액USD]
      rows = []
      (0..7).each do |i|
        base    = Date.today << (i * 3)
        q_start = base.beginning_of_quarter
        q_end   = base.end_of_quarter
        orders  = Order.where(created_at: q_start..q_end)
        del     = orders.where(status: "delivered")
        ot      = del.where("due_date >= date(updated_at)")
        rate    = del.count > 0 ? (ot.count.to_f / del.count * 100).round(1) : 0
        rows << [
          q_start.year,
          "Q#{(q_start.month / 3.0).ceil}",
          orders.count, del.count, rate,
          orders.sum(:estimated_value).to_f.round(0),
          orders.maximum(:estimated_value).to_f.round(0)
        ]
      end
      update_sheet("분기데이터", headers, rows.reverse)
    end

    # ── 현장별 실적 ───────────────────────────────────────────
    def sync_site_category(log)
      headers = %w[현장분류 현장명 발주건수 납품건수 납기준수율 총수주금액USD 진행상태]
      rows = []

      Project.includes(:client).order(:site_category, :name).each do |project|
        po  = project.orders
        del = po.where(status: "delivered")
        ot  = del.where("due_date >= date(updated_at)")
        rate = del.count > 0 ? (ot.count.to_f / del.count * 100).round(1) : 0
        rows << [
          project.site_category || "기타", project.name,
          po.count, del.count, rate,
          po.sum(:estimated_value).to_f.round(0),
          project.status
        ]
      end

      un = Order.where(project_id: nil)
      if un.count > 0
        del  = un.where(status: "delivered")
        ot   = del.where("due_date >= date(updated_at)")
        rate = del.count > 0 ? (ot.count.to_f / del.count * 100).round(1) : 0
        rows << [ "미분류", "현장 미배정", un.count, del.count, rate,
                  un.sum(:estimated_value).to_f.round(0), "-" ]
      end

      update_sheet("현장별실적", headers, rows)
      log.update_column(:projects_count, rows.size)
    end

    # ── 발주 원데이터 500건 ───────────────────────────────────
    def sync_orders_raw(log)
      headers = %w[ID 제목 고객사 공급사 현장 상태 우선순위 납기일 품목 수량 견적가USD 담당자 생성일]
      rows = Order.includes(:client, :supplier, :project)
                  .order(created_at: :desc).limit(500)
                  .map do |o|
        [
          o.id, o.title,
          o.client&.name || o.customer_name,
          o.supplier&.name,
          o.project&.name,
          o.status, o.priority,
          o.due_date&.strftime("%Y-%m-%d"),
          o.item_name, o.quantity,
          o.estimated_value.to_f.round(0),
          o.assignees.first&.name || "-",
          o.created_at.strftime("%Y-%m-%d")
        ]
      end
      update_sheet("발주현황", headers, rows)
    end

    # ── HR 현황 ───────────────────────────────────────────────
    def sync_hr_status(log)
      emp_headers = %w[이름 국적 직책 부서 고용형태 입사일 상태]
      emp_rows = Employee.includes(:department).order(:active, :name).map do |e|
        [ e.name, e.nationality, e.job_title,
          e.department&.name || e.department,
          e.employment_type,
          e.hire_date&.strftime("%Y-%m-%d"),
          e.active? ? "재직" : "퇴직" ]
      end
      update_sheet("직원현황", emp_headers, emp_rows)

      visa_headers = %w[직원명 비자유형 발급국 비자번호 만료일 D-Day 경고레벨 상태]
      visa_rows = Visa.includes(:employee).order(:expiry_date).map do |v|
        days  = v.expiry_date ? (v.expiry_date - Date.today).to_i : nil
        level = case days
                when nil   then "N/A"
                when ..0   then "만료"
                when 1..30 then "긴급"
                when 31..60 then "경고"
                when 61..90 then "주의"
                else "정상"
                end
        [ v.employee&.name, v.visa_type, v.issuing_country,
          v.visa_number, v.expiry_date&.strftime("%Y-%m-%d"),
          days || "N/A", level, v.status ]
      end
      update_sheet("비자현황", visa_headers, visa_rows)

      log.update_column(:employees_count, emp_rows.size)
      log.update_column(:visas_count, visa_rows.size)
    end

    # ══════════════════════════════════════════════════════════
    # 대시보드 탭 구성 (차트 + 슬라이서)
    # ══════════════════════════════════════════════════════════
    def build_dashboard_tab
      ensure_sheet_exists("대시보드")
      sid = sheet_id_for("대시보드")
      monthly_sid = sheet_id_for("월별데이터")
      return unless sid && monthly_sid

      # 기존 차트/슬라이서 삭제 후 재생성
      requests = []
      requests += delete_existing_charts(sid)
      requests += delete_existing_slicers(sid)

      # KPI 스코어카드 헤더 텍스트 작성
      write_dashboard_kpi_header

      # 차트 추가 요청들
      requests += [ build_monthly_bar_chart(sid, monthly_sid) ]
      requests += [ build_site_category_pie_chart(sid) ]
      requests += [ build_quarterly_line_chart(sid) ]

      # 슬라이서 (기간 필터) 추가
      requests += [ build_month_slicer(sid, monthly_sid) ]

      return if requests.empty?

      batch = Google::Apis::SheetsV4::BatchUpdateSpreadsheetRequest.new(requests: requests)
      @service.batch_update_spreadsheet(spreadsheet_id, batch)
      Rails.logger.info "[SheetsService] 대시보드 탭 차트/슬라이서 구성 완료"
    end

    def delete_existing_charts(sheet_id)
      spreadsheet = @service.get_spreadsheet(spreadsheet_id)
      sheet = spreadsheet.sheets.find { |s| s.properties.sheet_id == sheet_id }
      return [] unless sheet&.charts

      sheet.charts.map do |chart|
        Google::Apis::SheetsV4::Request.new(
          delete_embedded_object: Google::Apis::SheetsV4::DeleteEmbeddedObjectRequest.new(
            object_id_prop: chart.chart_id
          )
        )
      end
    end

    def delete_existing_slicers(sheet_id)
      spreadsheet = @service.get_spreadsheet(spreadsheet_id)
      sheet = spreadsheet.sheets.find { |s| s.properties.sheet_id == sheet_id }
      return [] unless sheet&.slicers

      sheet.slicers.map do |slicer|
        Google::Apis::SheetsV4::Request.new(
          delete_slicer: Google::Apis::SheetsV4::DeleteSlicerRequest.new(
            slicer_id: slicer.slicer_id
          )
        )
      end
    end

    def write_dashboard_kpi_header
      today = Date.today

      active   = Order.where.not(status: "delivered").count
      overdue  = Order.where.not(status: "delivered").where("due_date < ?", today).count
      del_m    = Order.where(status: "delivered", updated_at: today.beginning_of_month..).count
      val_m    = Order.where(created_at: today.beginning_of_month..).sum(:estimated_value).to_f

      del_all  = Order.where(status: "delivered",
                             updated_at: today.beginning_of_month..today.end_of_month)
      ot       = del_all.where("due_date >= date(updated_at)").count
      rate     = del_all.count > 0 ? (ot.to_f / del_all.count * 100).round(1) : 0

      kpi_values = [
        [ "CPOFlow 경영 대시보드", "", "", "", "", "", "" ],
        [ "동기화: #{today.strftime('%Y년 %m월 %d일')}", "", "", "", "", "", "" ],
        [ "", "", "", "", "", "", "" ],
        [ "진행중 발주", "지연 발주", "이달 납품", "이달 수주액(USD)", "납기준수율(이달)", "", "" ],
        [ active, overdue, del_m, val_m.round(0), "#{rate}%", "", "" ],
        [ "", "", "", "", "", "", "" ],
        [ "← 월별 수주/납품 차트", "", "", "", "현장별 파이차트 →", "", "" ],
      ]

      range = "대시보드!A1"
      body  = Google::Apis::SheetsV4::ValueRange.new(values: kpi_values)
      @service.update_spreadsheet_value(spreadsheet_id, range, body,
                                        value_input_option: "USER_ENTERED")
    end

    # ── 차트 1: 월별 수주/납품 막대 차트 ─────────────────────
    def build_monthly_bar_chart(dashboard_sid, monthly_sid)
      # 월별데이터 시트: A=년월, B=수주건수, C=납품건수 (행 2~25)
      row_count = [ Order.count > 0 ? 25 : 3, 25 ].min

      chart_spec = Google::Apis::SheetsV4::ChartSpec.new(
        title: "월별 수주 / 납품 추이 (24개월)",
        basic_chart: Google::Apis::SheetsV4::BasicChartSpec.new(
          chart_type: "COLUMN",
          legend_position: "BOTTOM_LEGEND",
          header_count: 1,
          axis: [
            Google::Apis::SheetsV4::BasicChartAxis.new(
              position: "BOTTOM_AXIS",
              title: "년월"
            ),
            Google::Apis::SheetsV4::BasicChartAxis.new(
              position: "LEFT_AXIS",
              title: "건수"
            )
          ],
          domains: [
            Google::Apis::SheetsV4::BasicChartDomain.new(
              domain: Google::Apis::SheetsV4::ChartData.new(
                source_range: Google::Apis::SheetsV4::ChartSourceRange.new(
                  sources: [ grid_range(monthly_sid, 0, row_count, 0, 1) ]
                )
              )
            )
          ],
          series: [
            Google::Apis::SheetsV4::BasicChartSeries.new(
              series: Google::Apis::SheetsV4::ChartData.new(
                source_range: Google::Apis::SheetsV4::ChartSourceRange.new(
                  sources: [ grid_range(monthly_sid, 0, row_count, 1, 2) ]
                )
              ),
              target_axis: "LEFT_AXIS",
              color: rgb(0, 112, 192)   # 파란색 — 수주
            ),
            Google::Apis::SheetsV4::BasicChartSeries.new(
              series: Google::Apis::SheetsV4::ChartData.new(
                source_range: Google::Apis::SheetsV4::ChartSourceRange.new(
                  sources: [ grid_range(monthly_sid, 0, row_count, 2, 3) ]
                )
              ),
              target_axis: "LEFT_AXIS",
              color: rgb(0, 176, 80)    # 초록색 — 납품
            )
          ]
        )
      )

      Google::Apis::SheetsV4::Request.new(
        add_chart: Google::Apis::SheetsV4::AddChartRequest.new(
          chart: Google::Apis::SheetsV4::EmbeddedChart.new(
            spec: chart_spec,
            position: Google::Apis::SheetsV4::EmbeddedObjectPosition.new(
              overlay_position: Google::Apis::SheetsV4::OverlayPosition.new(
                anchor_cell: grid_coordinate(dashboard_sid, 7, 0),
                offset_x_pixels: 0,
                offset_y_pixels: 0,
                width_pixels: 560,
                height_pixels: 320
              )
            )
          )
        )
      )
    end

    # ── 차트 2: 현장 카테고리 파이 차트 ──────────────────────
    def build_site_category_pie_chart(dashboard_sid)
      cat_sid = sheet_id_for("현장별실적")
      return nil unless cat_sid

      # 현장별실적 시트에서 카테고리별 합계 행 (마지막 N행)
      nuclear_orders = Project.where(site_category: "nuclear").sum { |p| p.orders.count }
      hydro_orders   = Project.where(site_category: "hydro").sum { |p| p.orders.count }
      tunnel_orders  = Project.where(site_category: "tunnel").sum { |p| p.orders.count }
      gtx_orders     = Project.where(site_category: "gtx").sum { |p| p.orders.count }

      # 파이차트용 임시 데이터를 대시보드 시트 Z열에 기록
      pie_data = [
        [ "현장분류", "발주건수" ],
        [ "원전(Nuclear)", nuclear_orders ],
        [ "수력(Hydro)",   hydro_orders   ],
        [ "터널(Tunnel)",  tunnel_orders  ],
        [ "GTX",           gtx_orders     ]
      ]
      body = Google::Apis::SheetsV4::ValueRange.new(values: pie_data)
      @service.update_spreadsheet_value(spreadsheet_id, "대시보드!I1",
                                        body, value_input_option: "USER_ENTERED")

      pie_sid = sheet_id_for("대시보드")

      chart_spec = Google::Apis::SheetsV4::ChartSpec.new(
        title: "현장 카테고리별 발주 비중",
        pie_chart: Google::Apis::SheetsV4::PieChartSpec.new(
          legend_position: "RIGHT_LEGEND",
          pie_hole: 0.4,   # 도넛 차트
          domain: Google::Apis::SheetsV4::ChartData.new(
            source_range: Google::Apis::SheetsV4::ChartSourceRange.new(
              sources: [ grid_range(pie_sid, 1, 5, 8, 9) ]
            )
          ),
          series: Google::Apis::SheetsV4::ChartData.new(
            source_range: Google::Apis::SheetsV4::ChartSourceRange.new(
              sources: [ grid_range(pie_sid, 1, 5, 9, 10) ]
            )
          )
        )
      )

      Google::Apis::SheetsV4::Request.new(
        add_chart: Google::Apis::SheetsV4::AddChartRequest.new(
          chart: Google::Apis::SheetsV4::EmbeddedChart.new(
            spec: chart_spec,
            position: Google::Apis::SheetsV4::EmbeddedObjectPosition.new(
              overlay_position: Google::Apis::SheetsV4::OverlayPosition.new(
                anchor_cell: grid_coordinate(dashboard_sid, 7, 9),
                offset_x_pixels: 0,
                offset_y_pixels: 0,
                width_pixels: 380,
                height_pixels: 320
              )
            )
          )
        )
      )
    end

    # ── 차트 3: 분기별 납기준수율 꺾은선 차트 ────────────────
    def build_quarterly_line_chart(dashboard_sid)
      q_sid = sheet_id_for("분기데이터")
      return nil unless q_sid

      row_count = 9  # 헤더 + 8분기

      chart_spec = Google::Apis::SheetsV4::ChartSpec.new(
        title: "분기별 납기준수율 추이 (%)",
        basic_chart: Google::Apis::SheetsV4::BasicChartSpec.new(
          chart_type: "LINE",
          legend_position: "BOTTOM_LEGEND",
          header_count: 1,
          line_smoothing: true,
          axis: [
            Google::Apis::SheetsV4::BasicChartAxis.new(
              position: "BOTTOM_AXIS",
              title: "분기"
            ),
            Google::Apis::SheetsV4::BasicChartAxis.new(
              position: "LEFT_AXIS",
              title: "납기준수율 (%)"
            )
          ],
          domains: [
            Google::Apis::SheetsV4::BasicChartDomain.new(
              domain: Google::Apis::SheetsV4::ChartData.new(
                source_range: Google::Apis::SheetsV4::ChartSourceRange.new(
                  # 년도+분기 합쳐서 라벨 — B열(분기)만 사용
                  sources: [ grid_range(q_sid, 0, row_count, 1, 2) ]
                )
              )
            )
          ],
          series: [
            Google::Apis::SheetsV4::BasicChartSeries.new(
              series: Google::Apis::SheetsV4::ChartData.new(
                source_range: Google::Apis::SheetsV4::ChartSourceRange.new(
                  sources: [ grid_range(q_sid, 0, row_count, 4, 5) ]  # E열 = 납기준수율
                )
              ),
              target_axis: "LEFT_AXIS",
              color: rgb(255, 100, 0)   # 주황색
            )
          ]
        )
      )

      Google::Apis::SheetsV4::Request.new(
        add_chart: Google::Apis::SheetsV4::AddChartRequest.new(
          chart: Google::Apis::SheetsV4::EmbeddedChart.new(
            spec: chart_spec,
            position: Google::Apis::SheetsV4::EmbeddedObjectPosition.new(
              overlay_position: Google::Apis::SheetsV4::OverlayPosition.new(
                anchor_cell: grid_coordinate(dashboard_sid, 26, 0),
                offset_x_pixels: 0,
                offset_y_pixels: 0,
                width_pixels: 560,
                height_pixels: 280
              )
            )
          )
        )
      )
    end

    # ── 슬라이서: 월별데이터 A열(년월) 기간 필터 ─────────────
    def build_month_slicer(dashboard_sid, monthly_sid)
      Google::Apis::SheetsV4::Request.new(
        add_slicer: Google::Apis::SheetsV4::AddSlicerRequest.new(
          slicer: Google::Apis::SheetsV4::Slicer.new(
            spec: Google::Apis::SheetsV4::SlicerSpec.new(
              title: "기간 선택 (년월)",
              data_range: Google::Apis::SheetsV4::GridRange.new(
                sheet_id:          monthly_sid,
                start_row_index:   0,
                end_row_index:     25,
                start_column_index: 0,
                end_column_index:  7
              ),
              column_index: 0,   # A열(년월) 기준 필터
              apply_to_pivot_tables: false
            ),
            position: Google::Apis::SheetsV4::EmbeddedObjectPosition.new(
              overlay_position: Google::Apis::SheetsV4::OverlayPosition.new(
                anchor_cell: grid_coordinate(dashboard_sid, 7, 14),
                offset_x_pixels: 0,
                offset_y_pixels: 0,
                width_pixels: 200,
                height_pixels: 50
              )
            )
          )
        )
      )
    end

    # ── 헬퍼 ─────────────────────────────────────────────────
    def grid_range(sheet_id, start_row, end_row, start_col, end_col)
      Google::Apis::SheetsV4::GridRange.new(
        sheet_id:           sheet_id,
        start_row_index:    start_row,
        end_row_index:      end_row,
        start_column_index: start_col,
        end_column_index:   end_col
      )
    end

    def grid_coordinate(sheet_id, row, col)
      Google::Apis::SheetsV4::GridCoordinate.new(
        sheet_id:     sheet_id,
        row_index:    row,
        column_index: col
      )
    end

    def rgb(r, g, b)
      Google::Apis::SheetsV4::Color.new(
        red:   r / 255.0,
        green: g / 255.0,
        blue:  b / 255.0
      )
    end
  end
end
