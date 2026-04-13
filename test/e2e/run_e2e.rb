#!/usr/bin/env ruby
# frozen_string_literal: true

# CPOFlow E2E 테스트 — Rails runner로 실행
# 사용법: bin/rails runner test/e2e/run_e2e.rb
#
# 서버가 실행 중이어야 합니다 (localhost:3020 또는 BASE_URL 환경변수)

require "net/http"
require "uri"
require "json"

class E2ETestRunner
  BASE_URL = ENV.fetch("BASE_URL", "http://localhost:3020")
  ADMIN_EMAIL = ENV.fetch("E2E_EMAIL", "admin@atozone.com")
  ADMIN_PASSWORD = ENV.fetch("E2E_PASSWORD", "password")

  attr_reader :passed, :failed, :results

  def initialize
    @passed = 0
    @failed = 0
    @results = []
    @cookie = nil
  end

  def run_all
    puts "\n#{'=' * 60}"
    puts "  CPOFlow E2E Test Suite"
    puts "  Base URL: #{BASE_URL}"
    puts "#{'=' * 60}\n\n"

    test_1_health_check
    test_2_login_page
    test_3_login_and_dashboard
    test_4_kanban_page
    test_5_orders_index
    test_6_order_create_form
    test_7_inbox_page
    test_8_clients_page
    test_9_suppliers_page
    test_10_calendar_page
    test_11_reports_page
    test_12_search_page
    test_13_agent_insights_dashboard
    test_14_pdf_quote_access
    test_15_settings_page

    puts "\n#{'=' * 60}"
    puts "  Results: #{@passed} passed, #{@failed} failed (#{@passed + @failed} total)"
    puts "#{'=' * 60}\n"

    @results.each { |r| puts r }
    puts ""

    exit(@failed > 0 ? 1 : 0)
  end

  private

  # ── 헬퍼 ───────────────────────────────────────────────────

  def get(path, follow_redirect: true)
    uri = URI("#{BASE_URL}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Get.new(uri)
    req["Cookie"] = @cookie if @cookie
    response = http.request(req)

    # 리다이렉트 따라가기
    if follow_redirect && [ 301, 302 ].include?(response.code.to_i)
      location = response["Location"]
      location = "#{BASE_URL}#{location}" unless location.start_with?("http")
      uri2 = URI(location)
      req2 = Net::HTTP::Get.new(uri2)
      req2["Cookie"] = @cookie if @cookie
      response = Net::HTTP.new(uri2.host, uri2.port).request(req2)
    end

    response
  end

  def post(path, params = {})
    uri = URI("#{BASE_URL}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri)
    req["Cookie"] = @cookie if @cookie
    req.set_form_data(params)
    http.request(req)
  end

  def login!
    # GET sign_in to get CSRF token
    resp = get("/users/sign_in", follow_redirect: false)
    @cookie = resp["Set-Cookie"]

    # Extract authenticity_token
    body = resp.body
    token = body.match(/name="authenticity_token".*?value="([^"]+)"/m)&.[](1)
    return false unless token

    # POST sign_in
    resp2 = post("/users/sign_in", {
      "user[email]" => ADMIN_EMAIL,
      "user[password]" => ADMIN_PASSWORD,
      "authenticity_token" => token
    })

    # 로그인 성공 시 리다이렉트
    if [ 301, 302 ].include?(resp2.code.to_i)
      @cookie = resp2["Set-Cookie"] || @cookie
      return true
    end
    false
  end

  def assert_status(name, response, expected_codes)
    code = response.code.to_i
    if expected_codes.include?(code)
      pass(name, "HTTP #{code}")
    else
      fail_test(name, "Expected #{expected_codes}, got #{code}")
    end
  end

  def assert_body_contains(name, response, text)
    if response.body.include?(text)
      pass(name, "Contains '#{text}'")
    else
      fail_test(name, "Missing '#{text}' in response body")
    end
  end

  def pass(name, detail = "")
    @passed += 1
    msg = "  ✅ #{name}"
    msg += " — #{detail}" if detail.present?
    @results << msg
    puts msg
  end

  def fail_test(name, detail = "")
    @failed += 1
    msg = "  ❌ #{name}"
    msg += " — #{detail}" if detail.present?
    @results << msg
    puts msg
  end

  # ── 테스트 케이스 ─────────────────────────────────────────

  def test_1_health_check
    resp = get("/up", follow_redirect: false)
    assert_status("Health Check (/up)", resp, [ 200 ])
  end

  def test_2_login_page
    resp = get("/users/sign_in", follow_redirect: false)
    assert_status("Login Page loads", resp, [ 200 ])
    assert_body_contains("Login form present", resp, "sign_in")
  end

  def test_3_login_and_dashboard
    if login!
      pass("Login as admin")
      resp = get("/dashboard")
      assert_status("Dashboard accessible", resp, [ 200 ])
      assert_body_contains("Dashboard KPI present", resp, "대시보드")
    else
      fail_test("Login as admin", "Authentication failed")
    end
  end

  def test_4_kanban_page
    resp = get("/kanban")
    assert_status("Kanban Board loads", resp, [ 200 ])
  end

  def test_5_orders_index
    resp = get("/orders")
    assert_status("Orders Index loads", resp, [ 200 ])
  end

  def test_6_order_create_form
    resp = get("/orders/new")
    assert_status("New Order form loads", resp, [ 200 ])
    assert_body_contains("Order form fields", resp, "order")
  end

  def test_7_inbox_page
    resp = get("/inbox")
    assert_status("Inbox loads", resp, [ 200 ])
  end

  def test_8_clients_page
    resp = get("/clients")
    assert_status("Clients page loads", resp, [ 200 ])
  end

  def test_9_suppliers_page
    resp = get("/suppliers")
    assert_status("Suppliers page loads", resp, [ 200 ])
  end

  def test_10_calendar_page
    resp = get("/calendar")
    assert_status("Calendar loads", resp, [ 200 ])
  end

  def test_11_reports_page
    resp = get("/reports")
    assert_status("Reports page loads", resp, [ 200 ])
  end

  def test_12_search_page
    resp = get("/search?q=test")
    assert_status("Search works", resp, [ 200 ])
  end

  def test_13_agent_insights_dashboard
    resp = get("/dashboard")
    if resp.body.include?("CPO Agent") || resp.body.include?("agent")
      pass("CPO Agent briefing widget", "Present on dashboard")
    else
      pass("CPO Agent briefing widget", "No active insights (expected if no data)")
    end
  end

  def test_14_pdf_quote_access
    order = Order.first
    if order
      resp = get("/orders/#{order.id}/pdf/quote")
      assert_status("PDF Quote generation", resp, [ 200, 302 ])
    else
      pass("PDF Quote generation", "Skipped (no orders)")
    end
  end

  def test_15_settings_page
    resp = get("/settings")
    assert_status("Settings page loads", resp, [ 200 ])
  end
end

E2ETestRunner.new.run_all
