# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  include ApplicationHelper

  test "@멘션은 군청색(primary navy) 굵은 글씨 span으로 감싼다" do
    out = highlight_mentions("@홍길동 확인 부탁")
    assert_includes out, "text-primary"
    assert_includes out, "font-bold"
    assert_includes out, "#142844"  # bolder navy inline style
    assert_includes out, ">@홍길동</span>"
  end

  test "URL은 새 탭 링크로 변환" do
    out = highlight_mentions("참고: https://example.com/path")
    assert_includes out, "<a href=\"https://example.com/path\""
    assert_includes out, "target=\"_blank\""
    assert_includes out, "rel=\"noopener noreferrer\""
  end

  test "2개 이상 번호 매김이 한 줄에 있으면 각 번호 앞에 줄바꿈 삽입" do
    out = highlight_mentions("시작 1. 가 2. 나 3. 다")
    # 앞 공백 조건이라 "1." "2." "3." 모두 줄바꿈 삽입됨
    assert_equal 3, out.scan("<br>").size
  end

  test "번호 매김 1개뿐이면 불필요한 줄바꿈 없음" do
    out = highlight_mentions("Only 1. item here")
    refute_includes out, "<br>"
  end

  test "2개 이상 라벨(Website:/Contact:)이 있으면 각 라벨 앞에 줄바꿈" do
    txt = "Acme Corp Website: https://acme.test Contact: +1-555 Note: first line."
    out = highlight_mentions(txt)
    assert_includes out, "<br>Website: "
    assert_includes out, "<br>Contact: "
    assert_includes out, "<br>Note: "
  end

  test "'(Brand)' 같이 콜론 없는 괄호 단어는 줄바꿈하지 않는다" do
    out = highlight_mentions("desc (Hyosung Brand). next sentence.")
    refute_includes out, "<br>"
  end

  test "복수 @멘션 모두 하이라이트" do
    out = highlight_mentions("@홍길동 와 @김철수 모두 확인")
    assert_equal 2, out.scan(">@").size
  end

  test "개행(\\n)은 <br>로 변환" do
    out = highlight_mentions("첫줄\n둘째줄")
    assert_includes out, "첫줄<br>둘째줄"
  end

  test "빈 문자열 / nil 안전 처리" do
    assert_equal "", highlight_mentions("")
    assert_equal "", highlight_mentions(nil)
  end

  test "HTML 특수문자는 이스케이프 (XSS 방어)" do
    out = highlight_mentions("<script>alert(1)</script>")
    refute_includes out, "<script>"
    assert_includes out, "&lt;script&gt;"
  end
end
