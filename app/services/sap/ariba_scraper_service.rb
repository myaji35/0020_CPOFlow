# frozen_string_literal: true

# SAP Ariba 공급자 포털 자동 로그인 및 PDF 수집 서비스
# Playwright를 통한 브라우저 자동화 → ActiveStorage에 저장
module Sap
  class AribaScraperService
    # webjumper(문서 링크) + declineToResp(거절 링크) 등 /ad/ 하위 경로 전부 수집
    # Authenticator, login, pswdRe 등 인증 관련 링크는 제외
    ARIBA_LINK_PATTERN = %r{https?://(?:[a-z0-9\-]+\.)*ariba\.com/ad/(?!pswdRe|Authenticator)[^\s"'<>]*}i.freeze

    def initialize
      @username = Rails.application.credentials.dig(:sap_ariba, :username)
      @password = Rails.application.credentials.dig(:sap_ariba, :password)
    end

    # Order의 sap_portal_links에서 Ariba 링크 추출 → 접속 → PDF 수집 → ActiveStorage 저장
    # 반환: { saved: [blob_info, ...], errors: [...] }
    def fetch_pdfs_for_order(order)
      links = extract_ariba_links(order)

      if links.empty?
        Rails.logger.info "AribaScraperService: Ariba 링크 없음 (Order##{order.id})"
        return { saved: [], errors: [] }
      end

      Rails.logger.info "AribaScraperService: #{links.size}개 링크 발견 (Order##{order.id})"

      saved  = []
      errors = []

      links.each do |link|
        result = fetch_pdfs_from_link(link, order)
        saved.concat(result[:saved])
        errors.concat(result[:errors])
      end

      { saved: saved, errors: errors }
    end

    # Order에서 Ariba 링크 추출
    def self.extract_ariba_links(order)
      sap_links = JSON.parse(order.sap_portal_links.to_s) rescue []
      # sap_portal_links에서 Ariba 패턴 필터링
      ariba_links = sap_links.select { |url| url.match?(ARIBA_LINK_PATTERN) }

      # 이메일 본문에서도 추가 추출
      body_text = [order.original_email_body.to_s, order.original_email_html_body.to_s].join(" ")
      body_links = body_text.scan(ARIBA_LINK_PATTERN).uniq

      (ariba_links + body_links).uniq
    end

    private

    def extract_ariba_links(order)
      self.class.extract_ariba_links(order)
    end

    # 특정 Ariba 링크에 접속해 페이지 내 PDF 파일들 수집
    def fetch_pdfs_from_link(ariba_url, order)
      saved  = []
      errors = []

      require "playwright"

      Playwright.create(playwright_cli_executable_path: `which npx`.strip + " playwright") do |playwright|
        browser = playwright.chromium.launch(headless: true, args: ["--no-sandbox"])
        context = browser.new_context(
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36",
          accept_downloads: true
        )
        page = context.new_page

        begin
          Rails.logger.info "AribaScraperService: 접속 중 #{ariba_url}"
          page.goto(ariba_url, wait_until: "domcontentloaded", timeout: 30_000)

          if login_required?(page)
            Rails.logger.info "AribaScraperService: 로그인 수행"
            perform_login(page)
            page.goto(ariba_url, wait_until: "networkidle", timeout: 60_000)
          end

          page.wait_for_timeout(3000)

          pdf_links = find_pdf_links(page)
          Rails.logger.info "AribaScraperService: PDF 링크 #{pdf_links.size}개 발견"

          pdf_links.each do |link_ref|
            blob_info = download_and_attach_pdf(page, link_ref, order)
            if blob_info
              saved << blob_info
            else
              errors << "PDF 다운로드 실패: #{link_ref}"
            end
          end

        rescue => e
          Rails.logger.error "AribaScraperService: 오류 #{e.message}"
          errors << e.message
        ensure
          browser.close
        end
      end

      { saved: saved, errors: errors }
    rescue LoadError
      fetch_via_node_script(ariba_url, order)
    end

    # playwright gem 없을 때 Node.js 스크립트로 폴백
    def fetch_via_node_script(ariba_url, order)
      script_path = Rails.root.join("lib", "playwright", "ariba_pdf_fetcher.js")
      output_file = Rails.root.join("tmp", "ariba_pdfs_#{Time.now.to_i}.json")

      env = {
        "ARIBA_USERNAME"   => @username,
        "ARIBA_PASSWORD"   => @password,
        "ARIBA_TARGET_URL" => ariba_url,
        "ARIBA_OUTPUT_DIR" => Rails.root.join("storage", "attachments", "ariba").to_s
      }

      system(env, "node #{script_path} #{output_file}",
             out: Rails.root.join("log", "ariba_scraper.log").to_s,
             err: Rails.root.join("log", "ariba_scraper.log").to_s)

      saved  = []
      errors = []

      if File.exist?(output_file)
        results = JSON.parse(File.read(output_file)) rescue []
        File.delete(output_file) rescue nil

        results.each do |r|
          next unless r["path"] && File.exist?(r["path"])

          blob = ActiveStorage::Blob.create_and_upload!(
            io:           File.open(r["path"]),
            filename:     r["filename"],
            content_type: "application/pdf"
          )
          order.attachments.attach(blob)

          Rails.logger.info "AribaScraperService: #{r['filename']} 저장 (Order##{order.id})"
          saved << { filename: r["filename"], blob_key: blob.key }
        end
      else
        errors << "Node.js 스크립트 실행 실패"
      end

      { saved: saved, errors: errors }
    end

    def login_required?(page)
      page.query_selector('input[type="password"]') ||
        page.url.include?("login") ||
        page.url.include?("Authenticator")
    rescue
      false
    end

    def perform_login(page)
      username_field = page.wait_for_selector(
        'input[name="UserName"], input[type="email"], #username',
        timeout: 5000
      )
      username_field&.fill(@username)

      password_field = page.wait_for_selector(
        'input[type="password"]',
        timeout: 5000
      )
      password_field&.fill(@password)

      page.click('button[type="submit"]')
      page.wait_for_load_state("networkidle", timeout: 30_000)
    rescue => e
      Rails.logger.error "AribaScraperService: 로그인 실패 #{e.message}"
    end

    def find_pdf_links(page)
      page.query_selector_all('a[href*=".pdf"], a[title*=".pdf"]')
          .map { |el| el.get_attribute("href") }
          .compact
          .uniq
    rescue
      []
    end

    def download_and_attach_pdf(page, href, order)
      download = page.expect_download do
        page.goto(href)
      end

      filename  = File.basename(URI.parse(href).path).presence || "ariba_doc_#{Time.now.to_i}.pdf"
      safe_name = filename.gsub(/[^\w\.\-]/, "_")

      # 임시 파일에 저장 후 ActiveStorage에 업로드
      tmp_path = Rails.root.join("tmp", safe_name)
      download.save_as(tmp_path.to_s)

      blob = ActiveStorage::Blob.create_and_upload!(
        io:           File.open(tmp_path),
        filename:     safe_name,
        content_type: "application/pdf"
      )
      order.attachments.attach(blob)

      File.delete(tmp_path) rescue nil

      Rails.logger.info "AribaScraperService: #{safe_name} → ActiveStorage (Order##{order.id})"
      { filename: safe_name, blob_key: blob.key }
    rescue => e
      Rails.logger.error "AribaScraperService: PDF 다운로드 실패 #{e.message}"
      nil
    end
  end
end
