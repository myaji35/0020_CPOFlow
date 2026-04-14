# frozen_string_literal: true

require "test_helper"

class Gmail::BodyDecoderTest < ActiveSupport::TestCase
  test "decode — nil 반환 빈 문자열" do
    assert_equal "", Gmail::BodyDecoder.decode(nil)
  end

  test "decode — empty string 반환 빈 문자열" do
    assert_equal "", Gmail::BodyDecoder.decode("")
  end

  test "decode — base64url 인코딩 문자열 디코딩" do
    original = "Hello, World! 안녕하세요"
    encoded = Base64.urlsafe_encode64(original)
    result = Gmail::BodyDecoder.decode(encoded)
    assert_equal original, result
  end

  test "decode — 이미 디코딩된 UTF-8 문자열 그대로 반환" do
    text = +"이미 디코딩된 텍스트입니다."  # mutable string
    result = Gmail::BodyDecoder.decode(text)
    assert_equal text, result
  end

  test "decode_binary — nil 반환 nil" do
    assert_nil Gmail::BodyDecoder.decode_binary(nil)
  end

  test "decode_binary — empty string 반환 nil" do
    assert_nil Gmail::BodyDecoder.decode_binary("")
  end

  test "decode_binary — base64url 인코딩 바이너리 디코딩" do
    original = "binary data \x00\x01\x02"
    encoded = Base64.urlsafe_encode64(original)
    result = Gmail::BodyDecoder.decode_binary(encoded)
    assert_equal original, result
  end

  test "looks_like_base64url? — 유효한 base64url 문자열" do
    encoded = Base64.urlsafe_encode64("test data")
    assert Gmail::BodyDecoder.looks_like_base64url?(encoded)
  end

  test "looks_like_base64url? — 일반 한국어 텍스트는 false" do
    assert_not Gmail::BodyDecoder.looks_like_base64url?("안녕하세요 이것은 한국어 텍스트입니다")
  end

  test "looks_like_base64url? — nil이면 false" do
    assert_not Gmail::BodyDecoder.looks_like_base64url?(nil)
  end

  test "looks_like_base64url? — 공백 포함 문자열은 false" do
    assert_not Gmail::BodyDecoder.looks_like_base64url?("hello world this has spaces")
  end
end
