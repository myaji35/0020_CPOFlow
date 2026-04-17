# frozen_string_literal: true

module Admin
  class ImportsController < ApplicationController
    before_action :require_manager!
    before_action :set_import, only: %i[show download_errors retry_errors]

    # GET /admin/imports
    def index
      @imports = ImportLog.includes(:user)
                          .order(created_at: :desc)
                          .limit(50)
    end

    # GET /admin/imports/new
    def new
      @import = ImportLog.new
    end

    # POST /admin/imports
    def create
      file = params[:import_log][:import_file]
      type = params[:import_log][:import_type]

      unless file
        redirect_to new_admin_import_path, alert: "파일을 선택해주세요." and return
      end

      unless %w[products suppliers orders].include?(type)
        redirect_to new_admin_import_path, alert: "이관 유형을 선택해주세요." and return
      end

      # 미리보기 데이터 생성 (상위 5행)
      preview = generate_preview(file.tempfile.path, file.original_filename)

      @import = ImportLog.create!(
        user:        current_user,
        import_type: type,
        filename:    file.original_filename,
        status:      :pending,
        total_rows:  0,
        success_rows: 0,
        error_rows:  0,
        preview_data: preview.to_json
      )
      @import.import_file.attach(file)

      # 대용량 파일은 백그라운드, 소용량은 즉시 처리
      EcountImportJob.perform_later(@import.id)

      redirect_to admin_import_path(@import),
                  notice: t("admin.imports.create_success")
    end

    # GET /admin/imports/:id
    def show
      @errors_preview = JSON.parse(@import.error_details || "[]").first(10)
      @preview_rows   = JSON.parse(@import.preview_data  || "[]")
    end

    # ISS-219: POST /admin/imports/:id/retry_errors
    # 실패한 행들만으로 새 ImportLog 생성 → 재실행
    # 원본 파일의 error_details에 저장된 row 인덱스를 추출해 신규 CSV 생성
    def retry_errors
      errors = @import.error_rows_array
      if errors.empty?
        redirect_to admin_import_path(@import), alert: "재처리할 실패 행이 없습니다." and return
      end

      unless @import.import_file.attached?
        redirect_to admin_import_path(@import), alert: "원본 파일이 없어 재처리 불가" and return
      end

      # 원본 파일에서 실패 행만 추출 → 임시 CSV 생성
      failed_row_numbers = errors.map { |e| e["row"].to_i }.uniq.sort
      require "csv"
      require "tempfile"

      # 원본 로드 (Blob → temp file)
      blob = @import.import_file.blob
      ext  = File.extname(blob.filename.to_s).downcase
      tmp_in = Tempfile.new([ "retry_in_", ext ])
      tmp_in.binmode
      blob.download { |chunk| tmp_in.write(chunk) }
      tmp_in.close

      # 실패 행만 뽑아 새 CSV 생성 (XLSX도 CSV로 일단 변환)
      parser = Ecount::EcountParser.new(tmp_in.path)
      # EcountParser는 preview(n:)를 지원. 전체는 별도 메서드가 있다 가정 → fallback으로 CSV 재구성
      # 안전을 위해 CSV로 직접 읽기
      tmp_out = Tempfile.new([ "retry_out_", ".csv" ])
      tmp_out.write("\xEF\xBB\xBF")  # UTF-8 BOM for Excel
      headers_written = false
      line_idx = 0
      File.foreach(tmp_in.path, encoding: "BOM|UTF-8") do |line|
        line_idx += 1
        if line_idx == 1
          tmp_out.write(line)
          headers_written = true
          next
        end
        tmp_out.write(line) if failed_row_numbers.include?(line_idx)
      end
      tmp_out.close

      new_filename = "retry_#{@import.id}_#{@import.filename}"
      # 새 ImportLog 생성 + attach
      new_import = ImportLog.create!(
        user:        current_user,
        import_type: @import.import_type,
        filename:    new_filename,
        status:      :pending,
        total_rows:  0,
        success_rows: 0,
        error_rows:  0,
        preview_data: "[]"
      )
      new_import.import_file.attach(
        io: File.open(tmp_out.path),
        filename: new_filename,
        content_type: "text/csv"
      )

      tmp_in.unlink
      tmp_out.unlink

      EcountImportJob.perform_later(new_import.id)

      redirect_to admin_import_path(new_import),
                  notice: "실패 #{failed_row_numbers.size}건 재처리를 시작했습니다."
    rescue => e
      Rails.logger.error "[ImportsController#retry_errors] #{e.class}: #{e.message}"
      redirect_to admin_import_path(@import), alert: "재처리 실패: #{e.message.truncate(120)}"
    end

    # GET /admin/imports/:id/download_errors
    def download_errors
      if @import.result_file_path.blank?
        redirect_to admin_import_path(@import), alert: "에러 리포트 파일이 없습니다." and return
      end
      path = Rails.root.join("public", @import.result_file_path.to_s.sub(/^\//, "")).cleanpath
      unless path.to_s.start_with?(Rails.root.join("public").to_s)
        redirect_to admin_import_path(@import), alert: "잘못된 파일 경로입니다."
        return
      end
      if path.file?
        send_file path,
                  filename: "import_#{@import.id}_errors.csv",
                  type: "text/csv",
                  disposition: "attachment"
      else
        redirect_to admin_import_path(@import), alert: "에러 리포트 파일이 없습니다."
      end
    end

    private

    def set_import
      @import = ImportLog.find(params[:id])
    end

    def generate_preview(file_path, filename)
      ext = File.extname(filename).downcase
      Ecount::EcountParser.new(file_path).preview(n: 5)
    rescue => e
      Rails.logger.warn "[ImportsController] Preview failed: #{e.message}"
      []
    end
  end
end
