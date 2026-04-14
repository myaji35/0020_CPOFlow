# frozen_string_literal: true

require "test_helper"
require "tempfile"

class Ecount::EcountParserTest < ActiveSupport::TestCase
  test "HEADER_MAP 상수 정의됨" do
    assert Ecount::EcountParser::HEADER_MAP.is_a?(Hash)
    assert Ecount::EcountParser::HEADER_MAP.key?("품목코드")
  end

  test "parse — 존재하지 않는 파일 경로는 예외 발생" do
    assert_raises(StandardError) do
      Ecount::EcountParser.new("/nonexistent/path/file.csv").parse
    end
  end

  test "parse — CSV UTF-8 파일 파싱" do
    csv_content = "품목코드,품목명,단위\nP001,테스트품목,EA\nP002,두번째품목,PCS\n"
    Tempfile.create(["ecount_test", ".csv"], encoding: "UTF-8") do |f|
      f.write(csv_content)
      f.flush
      rows = Ecount::EcountParser.new(f.path).parse
      assert rows.is_a?(Array)
      assert rows.length == 2
      assert_equal "P001", rows[0][:ecount_code]
      assert_equal "테스트품목", rows[0][:name]
    end
  end

  test "parse — 빈 CSV 파일은 빈 배열" do
    Tempfile.create(["ecount_empty", ".csv"], encoding: "UTF-8") do |f|
      f.write("품목코드,품목명\n")
      f.flush
      rows = Ecount::EcountParser.new(f.path).parse
      assert_equal [], rows
    end
  end

  test "parse — 알 수 없는 헤더도 오류 없이 처리" do
    csv_content = "알수없는헤더,품목명\nVAL001,테스트\n"
    Tempfile.create(["ecount_unk", ".csv"], encoding: "UTF-8") do |f|
      f.write(csv_content)
      f.flush
      assert_nothing_raised do
        Ecount::EcountParser.new(f.path).parse
      end
    end
  end
end
