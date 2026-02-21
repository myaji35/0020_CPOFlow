# frozen_string_literal: true

module Ecount
  # eCount 파일을 파싱하고 CPOFlow DB에 Upsert 처리하는 핵심 서비스
  class EcountImportService
    BATCH_SIZE = 500

    def initialize(import_log)
      @log  = import_log
      @user = import_log.user
    end

    def run!
      file_path = download_file

      # 1. 파싱
      rows = EcountParser.new(file_path).parse
      @log.update!(total_rows: rows.size, status: :processing)

      # 2. 전략 선택
      strat = strategy

      # 3. 배치 처리
      success_count = 0
      errors        = []

      rows.each_slice(BATCH_SIZE).with_index do |batch, batch_idx|
        batch.each_with_index do |row, row_idx|
          global_row = batch_idx * BATCH_SIZE + row_idx + 2  # 1-indexed, header=1

          result = strat.upsert(row)
          if result[:ok]
            success_count += 1
          else
            errors << { row: global_row, data: row.slice(:ecount_code, :name), error: result[:error] }
          end
        end

        # 진행률 업데이트 (배치 완료마다)
        @log.update_columns(
          success_rows: success_count,
          error_rows:   errors.size
        )
      end

      # 4. 에러 리포트 생성
      report_path = generate_error_report(errors) if errors.any?

      # 5. 최종 업데이트
      @log.update!(
        status:           :completed,
        success_rows:     success_count,
        error_rows:       errors.size,
        error_details:    errors.to_json,
        result_file_path: report_path,
        completed_at:     Time.current
      )

      Rails.logger.info "[EcountImport] #{@log.import_type}: #{success_count} ok, #{errors.size} errors (log ##{@log.id})"
      { success: success_count, errors: errors.size }
    rescue => e
      @log.update!(status: :failed, error_details: [{ row: 0, error: e.message }].to_json)
      Rails.logger.error "[EcountImport] Failed: #{e.class} — #{e.message}"
      raise
    ensure
      File.delete(file_path) if file_path && File.exist?(file_path)
    end

    private

    def strategy
      case @log.import_type
      when "products"  then Strategies::ProductImportStrategy.new
      when "suppliers" then Strategies::SupplierImportStrategy.new
      when "orders"    then Strategies::OrderImportStrategy.new(@user)
      else raise ArgumentError, "알 수 없는 import_type: #{@log.import_type}"
      end
    end

    # ActiveStorage 첨부 파일을 임시 파일로 다운로드
    def download_file
      tmpfile = Tempfile.new(["ecount_import", File.extname(@log.filename.to_s)])
      tmpfile.binmode
      @log.import_file.download { |chunk| tmpfile.write(chunk) }
      tmpfile.flush
      tmpfile.path
    end

    # 에러 행을 CSV로 저장 (public/system/import_errors/ 아래)
    def generate_error_report(errors)
      dir  = Rails.root.join("public", "system", "import_errors")
      FileUtils.mkdir_p(dir)
      path = dir.join("import_#{@log.id}_errors.csv")

      CSV.open(path, "w", encoding: "UTF-8") do |csv|
        csv << %w[행번호 ecount_code 품목명 오류내용]
        errors.each do |e|
          csv << [e[:row], e.dig(:data, :ecount_code), e.dig(:data, :name), e[:error]]
        end
      end

      "/system/import_errors/import_#{@log.id}_errors.csv"
    end
  end
end
