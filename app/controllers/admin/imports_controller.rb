# frozen_string_literal: true

module Admin
  class ImportsController < ApplicationController
    before_action :require_manager!
    before_action :set_import, only: %i[show download_errors]

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
                  notice: "이관이 시작되었습니다. 잠시 후 결과를 확인하세요."
    end

    # GET /admin/imports/:id
    def show
      @errors_preview = JSON.parse(@import.error_details || "[]").first(10)
      @preview_rows   = JSON.parse(@import.preview_data  || "[]")
    end

    # GET /admin/imports/:id/download_errors
    def download_errors
      path = Rails.root.join("public", @import.result_file_path.to_s.sub(/^\//, ""))
      if path.exist?
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
