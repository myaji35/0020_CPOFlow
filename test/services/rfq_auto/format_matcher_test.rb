require "test_helper"

module RfqAuto
  class FormatMatcherTest < ActiveSupport::TestCase
    SAMPLE_NAWAH_PO = <<~TXT.freeze
      PURCHASE ORDER

      Nawah Energy Company
      PO NO                                4500020346
      VER    0
      DATE       13 Apr 2026
      REV. DATE     13 Apr 2026
      RFQ NO    6100002500

      START OF MESSAGE CODE Z_NPE_CMTR
      EACH ITEM ORDERED FOR WHICH THIS QUALITY STATEMENT IS SPECIFIED SHALL REQUIRE A MATERIAL TEST REPORT (MTR).
      END OF MESSAGE CODE Z_NPE_CMTR

      START OF MESSAGE CODE Z_NPE_PC3 MATERIAL
      THIS MATERIAL IS CLASSIFIED BY NAWAH ENERGY COMPANY (NAWAH) AS AUGMENTED QUALITY.
      END OF MESSAGE CODE Z_NPE_PC3 MATERIAL
    TXT

    SAMPLE_NAWAH_RFQ = <<~TXT.freeze
      REQUEST FOR QUOTATION

      RFQ NO                              6100002746
      DATE       29 Apr 26
      RFQ DEADLINE DATE     04 May 26

      START OF MESSAGE CODE Z_NPE_COMMERCIAL QA
      THE SUPPLIER'S COMMERCIAL QUALITY ASSURANCE PROGRAM APPLIES TO THIS PROCUREMENT.
      END OF MESSAGE CODE Z_NPE_COMMERCIAL QA
    TXT

    SAMPLE_ARIBA_LOGIN = <<~TXT.freeze
      Ariba Proposals and Questionnaires

      Supplier Login
      User Name
      Password

      © 2026 SAP SE or an SAP affiliate company.
    TXT

    test "NAWAH PO format detected and PO number extracted" do
      m = FormatMatcher.new(SAMPLE_NAWAH_PO)
      assert_equal "NAWAH PO Standard", m.format_name
      assert_not m.invalid?
      assert_equal "4500020346", m.fields[:po_number]
      assert m.must_comply.any? { |x| x[:category].to_s.match?(/MTR|CMTR/) }
      assert m.must_comply.any? { |x| x[:category].to_s.include?("PC3") }
    end

    test "NAWAH RFQ format detected" do
      m = FormatMatcher.new(SAMPLE_NAWAH_RFQ)
      assert_equal "NAWAH RFQ Standard", m.format_name
      assert_equal "6100002746", m.fields[:rfq_number]
      assert m.must_comply.any? { |x| x[:category].to_s.include?("Commercial QA") }
    end

    test "Ariba login page is flagged invalid" do
      m = FormatMatcher.new(SAMPLE_ARIBA_LOGIN)
      assert m.invalid?, "expected invalid? true"
      assert_empty m.fields
    end

    test "short text returns nil format gracefully" do
      m = FormatMatcher.new("hello world")
      assert_nil m.format_name
      assert_empty m.fields
      assert_empty m.must_comply
    end
  end
end
