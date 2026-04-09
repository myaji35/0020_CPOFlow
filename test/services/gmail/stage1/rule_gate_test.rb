# frozen_string_literal: true

require "test_helper"

class Gmail::Stage1::RuleGateTest < ActiveSupport::TestCase
  # ===== whitelist 도메인 =====
  test "whitelist domain: kepco.co.kr → whitelist_fast" do
    email = { subject: "Hello", from: "buyer <buyer@kepco.co.kr>", body: "안녕하세요" }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :whitelist_fast, result.action
    assert_equal "whitelist_domain", result.reason
    assert result.pass?
  end

  test "whitelist domain: adnoc.ae → whitelist_fast" do
    email = { subject: "No keywords here", from: "procurement@adnoc.ae", body: "Short text" }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :whitelist_fast, result.action
  end

  test "whitelist domain with mixed case: KEPCO.CO.KR" do
    email = { subject: "test", from: "BUYER@KEPCO.CO.KR", body: "" }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :whitelist_fast, result.action
  end

  # ===== 강 RFQ 키워드 =====
  test "strong keyword English: RFQ in subject" do
    email = { subject: "RFQ for concrete admixture", from: "buyer@unknown.com", body: "please quote" }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :pass_to_llm, result.action
    assert_equal "strong_keyword", result.reason
  end

  test "strong keyword English: Request for Quotation" do
    email = { subject: "Request for Quotation #123", from: "buyer@unknown.com", body: "" }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :pass_to_llm, result.action
  end

  test "strong keyword English: Tender" do
    email = { subject: "Tender announcement", from: "ops@random.com", body: "" }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :pass_to_llm, result.action
  end

  test "strong keyword Korean: 견적요청" do
    email = { subject: "[견적요청] 사이카 제품", from: "foo@random.co.kr", body: "" }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :pass_to_llm, result.action
    assert_equal "strong_keyword", result.reason
  end

  test "strong keyword Korean: 견적 의뢰 (with space)" do
    email = { subject: "견적 의뢰 드립니다", from: "foo@random.co.kr", body: "" }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :pass_to_llm, result.action
  end

  test "strong keyword Arabic: طلب عرض" do
    email = { subject: "طلب عرض سعر", from: "foo@random.ae", body: "" }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :pass_to_llm, result.action
  end

  # ===== 약 신호 =====
  test "weak signal: Sika product in body" do
    email = {
      subject: "Hello",
      from: "foo@random.com",
      body: "We need SikaGrout 212 for our project"
    }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :pass_to_llm, result.action
    assert_equal "weak_signal", result.reason
  end

  test "weak signal: concrete + quantity unit" do
    email = {
      subject: "project",
      from: "foo@random.com",
      body: "we need 5000 kg of concrete admixture"
    }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :pass_to_llm, result.action
  end

  test "weak signal: currency in body" do
    email = {
      subject: "inquiry",
      from: "foo@random.com",
      body: "Budget USD 50000 for waterproofing"
    }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :pass_to_llm, result.action
  end

  test "weak signal Korean: 납기 단가" do
    email = {
      subject: "문의",
      from: "foo@random.co.kr",
      body: "납기와 단가 문의드립니다"
    }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :pass_to_llm, result.action
  end

  # ===== reject (신호 0개) =====
  test "no signal: generic email → reject_no_signal" do
    email = {
      subject: "회식 안내",
      from: "hr@mycompany.com",
      body: "이번 주 금요일 회식 안내입니다"
    }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :reject_no_signal, result.action
    assert result.reject?
    assert_empty result.signals
  end

  test "no signal: newsletter style" do
    email = {
      subject: "Weekly newsletter issue 42",
      from: "news@random.com",
      body: "This week's updates from our team"
    }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :reject_no_signal, result.action
  end

  test "no signal: promotional email" do
    email = {
      subject: "Limited time offer",
      from: "marketing@shop.com",
      body: "Get 50% off on your first purchase"
    }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :reject_no_signal, result.action
  end

  # ===== 우선순위 (whitelist > strong > weak) =====
  test "whitelist takes precedence over keywords" do
    email = {
      subject: "Nothing interesting",
      from: "someone@kepco.co.kr",
      body: "nothing here"
    }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :whitelist_fast, result.action
  end

  test "strong keyword takes precedence over weak" do
    email = {
      subject: "RFQ - need 100 kg of SikaGrout",
      from: "foo@random.com",
      body: ""
    }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal "strong_keyword", result.reason
  end

  # ===== edge cases =====
  test "nil from handling" do
    email = { subject: "RFQ", from: nil, body: "request for quote" }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :pass_to_llm, result.action  # 강 키워드로 pass
  end

  test "empty body handling" do
    email = { subject: "", from: "foo@random.com", body: "" }
    result = Gmail::Stage1::RuleGate.decide(email)
    assert_equal :reject_no_signal, result.action
  end

  test "very long body truncated to 4000 chars" do
    body = "filler text " * 1000 + " SikaGrout"  # Sika가 4000자 이후에 있음
    email = { subject: "test", from: "foo@random.com", body: body }
    result = Gmail::Stage1::RuleGate.decide(email)
    # 4000자 이후는 무시 → reject 예상
    assert_equal :reject_no_signal, result.action
  end

  test "Result#pass? and Result#reject? helpers" do
    pass_result = Gmail::Stage1::RuleGate::Result.new(:pass_to_llm, "strong", [])
    assert pass_result.pass?
    refute pass_result.reject?

    reject_result = Gmail::Stage1::RuleGate::Result.new(:reject_no_signal, "none", [])
    refute reject_result.pass?
    assert reject_result.reject?
  end
end
